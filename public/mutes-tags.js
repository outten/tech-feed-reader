/* AJAX handlers for mute rules (/feeds) and tag rules (/tags).
 *
 * Both pages have long content — a full reload scrolls back to the
 * top. These handlers intercept form submits, POST via fetch with
 * Accept: application/json, and update the DOM in place so the user
 * stays exactly where they were.
 *
 * Mute add  : js-mute-add   → POST /mutes
 * Mute del  : js-mute-delete → POST /mutes/delete
 * Tag add   : js-tag-add    → POST /tags
 * Tag del   : js-tag-delete  → POST /tags/:id/delete
 */
(function () {
  'use strict';

  /* ── helpers ─────────────────────────────────────────────────────── */

  function flash(msg, kind) {
    var el = document.getElementById('flash-mount');
    if (!el) return;
    var div = document.createElement('div');
    div.className = kind === 'error' ? 'error' : 'notice';
    div.textContent = msg;
    el.replaceChildren(div);
    clearTimeout(flash._t);
    flash._t = setTimeout(function () {
      if (el.firstChild === div) el.replaceChildren();
    }, 5000);
  }

  function post(url, form) {
    return fetch(url, {
      method: 'POST',
      credentials: 'same-origin',
      headers: { 'Accept': 'application/json',
                 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams(new FormData(form)).toString()
    }).then(function (r) {
      return r.json().then(function (d) { return { ok: r.ok, status: r.status, data: d }; });
    });
  }

  /* ── mute add ─────────────────────────────────────────────────────── */

  document.addEventListener('submit', function (e) {
    var form = e.target.closest('form.js-mute-add');
    if (!form) return;
    e.preventDefault();

    var btn = form.querySelector('button[type="submit"]');
    if (btn) btn.disabled = true;

    post('/mutes', form).then(function (r) {
      if (btn) btn.disabled = false;
      if (!r.ok) {
        flash(r.data.message || 'Could not add mute rule.', 'error');
        return;
      }
      if (!r.data.added) {
        flash('That mute rule already exists.', 'error');
        return;
      }

      var kind  = r.data.kind;
      var value = r.data.value;

      // Build the new <li> and insert into the correct <ul>, creating
      // the heading + list if this is the first rule of that kind.
      var section = document.querySelector('.mutes-section');
      if (!section) { location.reload(); return; }

      var heading = Array.from(section.querySelectorAll('h4.catalog-category'))
                         .find(function (h) { return h.textContent.trim().toLowerCase().startsWith(kind); });

      if (!heading) {
        // First rule of this kind — inject heading + empty list
        var insertBefore = section.querySelector('p.subtitle:last-of-type') ||
                           section.querySelector('.mutes-add') || null;
        var h4 = document.createElement('h4');
        h4.className = 'catalog-category';
        h4.textContent = kind.charAt(0).toUpperCase() + kind.slice(1) + ' (0)';
        var ul = document.createElement('ul');
        ul.className = 'mute-list';
        if (insertBefore && insertBefore.parentNode) {
          insertBefore.parentNode.insertBefore(h4, insertBefore);
          insertBefore.parentNode.insertBefore(ul, insertBefore);
        } else {
          section.appendChild(h4);
          section.appendChild(ul);
        }
        heading = h4;
      }

      var list = heading.nextElementSibling;
      if (!list || list.tagName !== 'UL') { location.reload(); return; }

      var li = document.createElement('li');
      li.className = 'mute-row';
      li.innerHTML =
        '<span class="mute-value">' + escHtml(value) + '</span>' +
        '<span class="muted mute-since">just now</span>' +
        '<form method="post" action="/mutes/delete" style="display:inline" class="js-mute-delete">' +
          '<input type="hidden" name="kind" value="' + escHtml(kind) + '">' +
          '<input type="hidden" name="value" value="' + escHtml(value) + '">' +
          '<button type="submit" class="danger" title="Remove this mute rule">Unmute</button>' +
        '</form>';
      list.insertAdjacentElement('afterbegin', li);

      // Update count in heading
      var count = list.querySelectorAll('li.mute-row').length;
      heading.textContent = kind.charAt(0).toUpperCase() + kind.slice(1) + ' (' + count + ')';

      // Update section count in h3
      updateMuteCount(section, 1);

      // Hide "no rules yet" placeholder
      var empty = section.querySelector('p.subtitle:not(.subtitle ~ .subtitle)');
      if (empty && empty.textContent.trim().startsWith('No mute rules')) empty.style.display = 'none';

      form.reset();
      flash('Muted "' + value + '" (' + kind + '). Matching articles hidden.');
    });
  });

  /* ── mute delete ─────────────────────────────────────────────────── */

  document.addEventListener('submit', function (e) {
    var form = e.target.closest('form.js-mute-delete');
    if (!form) return;
    e.preventDefault();

    var kind  = (form.querySelector('input[name="kind"]')  || {}).value || '';
    var value = (form.querySelector('input[name="value"]') || {}).value || '';

    post('/mutes/delete', form).then(function (r) {
      if (!r.ok && !r.data.removed) {
        flash('Could not remove mute rule.', 'error');
        return;
      }
      var li = form.closest('li.mute-row');
      var ul = li && li.closest('ul.mute-list');
      var h4 = ul && ul.previousElementSibling;
      if (li) li.remove();

      // Update or remove heading
      if (ul && h4 && h4.tagName === 'H4') {
        var remaining = ul.querySelectorAll('li.mute-row').length;
        if (remaining === 0) {
          h4.remove(); ul.remove();
        } else {
          var kindLabel = kind.charAt(0).toUpperCase() + kind.slice(1);
          h4.textContent = kindLabel + ' (' + remaining + ')';
        }
      }

      var section = document.querySelector('.mutes-section');
      if (section) updateMuteCount(section, -1);

      flash('Mute rule removed. Matching articles visible again.');
    });
  });

  function updateMuteCount(section, delta) {
    var h3 = section && section.querySelector('h3');
    if (!h3) return;
    var span = h3.querySelector('span.muted');
    if (!span) return;
    var m = span.textContent.match(/(\d+)/);
    if (!m) return;
    var n = Math.max(0, parseInt(m[1], 10) + delta);
    span.textContent = '(' + n + ' rule' + (n === 1 ? '' : 's') + ')';
  }

  /* ── tag add ─────────────────────────────────────────────────────── */

  document.addEventListener('submit', function (e) {
    var form = e.target.closest('form.js-tag-add');
    if (!form) return;
    e.preventDefault();

    var btn = form.querySelector('button[type="submit"]');
    if (btn) btn.disabled = true;

    post('/tags', form).then(function (r) {
      if (btn) btn.disabled = false;
      if (!r.ok) {
        var msgs = {
          'missing-fields':  'Name and match value are required.',
          'invalid-kind':    'match_kind must be one of: regex, keyword, feed_id.',
          'invalid-regex':   'That regex didn\'t compile.',
          'duplicate-name':  'A tag with that name already exists.'
        };
        flash(msgs[r.data.error] || 'Could not add tag rule.', 'error');
        return;
      }

      var tag    = r.data.tag;
      var tagged = r.data.tagged || 0;

      // Add row to existing table, or reload if table doesn't exist yet
      var tbody = document.querySelector('table.data-table tbody');
      if (!tbody) { location.reload(); return; }

      var row = document.createElement('tr');
      row.innerHTML =
        '<td><a class="tag-chip" href="/articles?tag=' + escHtml(String(tag.id)) + '">' + escHtml(tag.name) + '</a></td>' +
        '<td class="muted">' + escHtml(tag.match_kind) + '</td>' +
        '<td><code>' + escHtml(tag.match_value) + '</code></td>' +
        '<td class="num">' + tagged + '</td>' +
        '<td>' +
          '<form method="post" action="/tags/' + escHtml(String(tag.id)) + '/delete" style="display:inline" class="js-tag-delete">' +
            '<button type="submit" class="danger" title="Delete this tag rule">Remove</button>' +
          '</form>' +
        '</td>';
      tbody.insertAdjacentElement('afterbegin', row);

      // Update tag count in subtitle
      var subtitle = document.querySelector('.page-header .subtitle');
      if (subtitle) {
        var rows = tbody.querySelectorAll('tr').length;
        subtitle.textContent = rows + ' tag' + (rows === 1 ? '' : 's') + '.';
      }

      form.reset();
      var msg = 'Tag "' + tag.name + '" added.';
      if (tagged > 0) msg += ' ' + tagged + ' existing article' + (tagged === 1 ? '' : 's') + ' tagged.';
      flash(msg);
    });
  });

  /* ── tag delete ─────────────────────────────────────────────────── */

  document.addEventListener('submit', function (e) {
    var form = e.target.closest('form.js-tag-delete');
    if (!form) return;
    e.preventDefault();

    if (!confirm('Remove this tag and all its associations?')) return;

    post(form.getAttribute('action'), form).then(function (r) {
      if (!r.ok) { flash('Could not remove tag.', 'error'); return; }
      var row = form.closest('tr');
      if (row) row.remove();

      var subtitle = document.querySelector('.page-header .subtitle');
      var tbody    = document.querySelector('table.data-table tbody');
      if (subtitle && tbody) {
        var rows = tbody.querySelectorAll('tr').length;
        subtitle.textContent = rows + ' tag' + (rows === 1 ? '' : 's') + '.';
      }

      flash('Tag removed.');
    });
  });

  /* ── util ────────────────────────────────────────────────────────── */

  function escHtml(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

})();
