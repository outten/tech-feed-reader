/* Floating chat widget. Sits on every page; opens a side panel that
 * lets the user chat with Claude about the current page.
 *
 * Storage model: per-page thread, persisted to localStorage under
 *   tfr.chat.<pathname>
 * so leaving and coming back to /article/abc keeps the conversation,
 * but moving to /podcasts gets a fresh thread.
 *
 * Server contract (POST /chat):
 *   request : { message, history: [{role, content}, ...], context: {url, title, excerpt} }
 *   response: { status: 'ok', reply, model, usage } on success
 *             { status: 'unavailable' | 'empty' | 'error', error } otherwise
 *
 * The widget hides itself entirely if /chat/health says Claude isn't
 * configured (no API key). That keeps the UI honest and avoids
 * flashing a button that always errors when clicked.
 */
(function () {
  'use strict';

  var root = document.getElementById('chat-widget');
  if (!root) return;
  // Guarded init — the chat-widget div is data-turbo-permanent so its
  // DOM + listeners survive Turbo navigations. The script body
  // re-executes on every body swap; this guard prevents double-binding
  // and avoids re-firing /chat/health on every page change.
  if (root.dataset.inited === '1') return;
  root.dataset.inited = '1';

  var toggleBtn = root.querySelector('#chat-widget-toggle');
  var panel     = root.querySelector('#chat-widget-panel');
  var contextEl = root.querySelector('.chat-panel-context');
  var clearBtn  = root.querySelector('.chat-panel-clear');
  var closeBtn  = root.querySelector('.chat-panel-close');
  var messagesEl = root.querySelector('.chat-panel-messages');
  var form      = root.querySelector('.chat-panel-form');
  var input     = root.querySelector('.chat-panel-input');
  var sendBtn   = root.querySelector('.chat-panel-send');

  var STORAGE_PREFIX = 'tfr.chat.';
  var MAX_HISTORY    = 16; // pairs we keep in localStorage; server caps independently

  // Read fresh on every call so Turbo navigations (which swap <body>
  // and replace the inline window.PAGE_CONTEXT script) are picked up
  // without a re-bootstrap.
  function currentStorageKey() { return STORAGE_PREFIX + (window.location.pathname || '/'); }
  function currentPageContext() {
    return window.PAGE_CONTEXT || { title: document.title, excerpt: '' };
  }

  // ---- bootstrap -------------------------------------------------------
  fetch('/chat/health', { credentials: 'same-origin' })
    .then(function (r) { return r.ok ? r.json() : { available: false }; })
    .catch(function () { return { available: false }; })
    .then(function (h) {
      if (!h.available) return; // leave widget hidden
      root.removeAttribute('hidden');
      paintContextLabel();
      renderHistory();
    });

  // Refresh per-page state when Turbo finishes a navigation. Without
  // this the widget would still reference the prior page's thread +
  // context excerpt.
  document.addEventListener('turbo:load', function () {
    paintContextLabel();
    renderHistory();
  });

  // ---- helpers ---------------------------------------------------------
  function loadHistory() {
    try {
      var raw = window.localStorage.getItem(currentStorageKey());
      if (!raw) return [];
      var parsed = JSON.parse(raw);
      return Array.isArray(parsed) ? parsed : [];
    } catch (_) { return []; }
  }

  function saveHistory(history) {
    try {
      var trimmed = history.slice(-MAX_HISTORY * 2);
      window.localStorage.setItem(currentStorageKey(), JSON.stringify(trimmed));
    } catch (_) {}
  }

  function clearHistory() {
    try { window.localStorage.removeItem(currentStorageKey()); } catch (_) {}
    messagesEl.innerHTML = '';
  }

  function paintContextLabel() {
    var t = (currentPageContext().title || '').trim();
    if (t.length > 60) t = t.slice(0, 57) + '…';
    contextEl.textContent = t ? 'about ' + t : '';
  }

  // Lightweight inline renderer: paragraphs + bullets + bold + code.
  // Markdown libraries would be overkill; this covers the model's
  // typical reply shapes and keeps the bundle zero-dep.
  function renderText(text) {
    var s = String(text || '');
    // escape HTML first
    s = s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    // **bold**
    s = s.replace(/\*\*([^*\n]+)\*\*/g, '<strong>$1</strong>');
    // `code`
    s = s.replace(/`([^`\n]+)`/g, '<code>$1</code>');
    // bullet lines (simple): leading "- " or "* " becomes <li>; group runs
    var lines = s.split(/\n/);
    var out = [], inList = false;
    lines.forEach(function (line) {
      if (/^\s*[-*]\s+/.test(line)) {
        if (!inList) { out.push('<ul>'); inList = true; }
        out.push('<li>' + line.replace(/^\s*[-*]\s+/, '') + '</li>');
      } else {
        if (inList) { out.push('</ul>'); inList = false; }
        out.push(line);
      }
    });
    if (inList) out.push('</ul>');
    return out.join('\n').replace(/\n{2,}/g, '<br><br>').replace(/\n/g, '<br>');
  }

  function appendMessage(role, content, isPending) {
    var msg = document.createElement('div');
    msg.className = 'chat-msg chat-msg-' + role + (isPending ? ' chat-msg-pending' : '');
    if (role === 'assistant') {
      msg.innerHTML = renderText(content);
    } else {
      msg.textContent = content;
    }
    messagesEl.appendChild(msg);
    messagesEl.scrollTop = messagesEl.scrollHeight;
    return msg;
  }

  function renderHistory() {
    messagesEl.innerHTML = '';
    var history = loadHistory();
    if (history.length === 0) {
      var hint = document.createElement('div');
      hint.className = 'chat-msg chat-msg-hint';
      hint.textContent = currentPageContext().excerpt
        ? 'Ask a question about this page — I can see its content.'
        : 'Ask anything. I don\'t have content from this page, so questions about it will be limited.';
      messagesEl.appendChild(hint);
      return;
    }
    history.forEach(function (m) { appendMessage(m.role, m.content, false); });
  }

  function setOpen(open) {
    panel.hidden = !open;
    toggleBtn.setAttribute('aria-expanded', open ? 'true' : 'false');
    if (open) {
      input.focus();
      messagesEl.scrollTop = messagesEl.scrollHeight;
    }
  }

  function send(message) {
    var history = loadHistory();
    history.push({ role: 'user', content: message });
    saveHistory(history);
    appendMessage('user', message, false);

    var pending = appendMessage('assistant', '…', true);
    sendBtn.disabled = true;
    input.disabled = true;

    fetch('/chat', {
      method: 'POST',
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
      body: JSON.stringify({
        message: message,
        history: history.slice(0, -1), // server gets prior turns; new message ships separately
        context: {
          url:     window.location.pathname,
          title:   currentPageContext().title || '',
          excerpt: currentPageContext().excerpt || ''
        }
      })
    })
      .then(function (r) {
        return r.json().then(function (j) { return { ok: r.ok, body: j }; });
      })
      .then(function (resp) {
        pending.classList.remove('chat-msg-pending');
        if (resp.ok && resp.body && resp.body.status === 'ok') {
          pending.innerHTML = renderText(resp.body.reply);
          history.push({ role: 'assistant', content: resp.body.reply });
          saveHistory(history);
        } else {
          pending.classList.add('chat-msg-error');
          var err = resp.body && resp.body.error ? resp.body.error : ('HTTP ' + (resp.body && resp.body.status));
          pending.textContent = 'Error: ' + err;
        }
      })
      .catch(function (e) {
        pending.classList.remove('chat-msg-pending');
        pending.classList.add('chat-msg-error');
        pending.textContent = 'Network error: ' + e.message;
      })
      .then(function () {
        sendBtn.disabled = false;
        input.disabled   = false;
        input.focus();
      });
  }

  // ---- wiring ----------------------------------------------------------
  toggleBtn.addEventListener('click', function () {
    setOpen(panel.hidden);
  });
  closeBtn.addEventListener('click', function () { setOpen(false); });
  clearBtn.addEventListener('click', function () {
    if (loadHistory().length === 0) { renderHistory(); return; }
    if (window.confirm('Clear this page\'s chat thread?')) {
      clearHistory();
      renderHistory();
    }
  });

  form.addEventListener('submit', function (e) {
    e.preventDefault();
    var msg = input.value.trim();
    if (!msg) return;
    input.value = '';
    send(msg);
  });

  // Enter sends; Shift+Enter inserts newline.
  input.addEventListener('keydown', function (e) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      form.requestSubmit();
    }
  });
})();
