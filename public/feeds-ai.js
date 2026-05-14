// STUFF.md #23 polish — UX wiring for the Ask-AI feed recommender.
//
// 1. On form submit, flip the inline "AI is thinking…" indicator on so the
//    user sees that the request is in flight (the server round-trip is
//    synchronous and takes 1–4s — without this the page just hangs).
// 2. On page load, if a result block is present from a prior submit,
//    scroll it into view + focus it so the response is impossible to miss.
//
// Re-runs on `turbo:load` so it survives soft navigation as well as a
// full reload.
//
// Gotcha: `button.disabled = true` inside the synchronous submit handler
// makes the browser drop the submission in some cases (the disabled
// button is no longer a valid form submitter). Defer the disable via
// setTimeout(0) so the request has already started before the property
// flips.

(function () {
  function wireSubmitIndicator() {
    var form = document.querySelector('.js-ai-recommend');
    if (!form) return;
    var indicator = form.querySelector('.ai-thinking');
    var button    = form.querySelector('button[type=submit]');
    form.addEventListener('submit', function () {
      if (indicator) indicator.classList.add('is-visible');
      if (button) {
        button.textContent = 'Thinking…';
        setTimeout(function () { button.disabled = true; }, 0);
      }
    });
  }

  function scrollResultIntoView() {
    var result = document.getElementById('ai-recommend-result');
    if (!result) return;
    // requestAnimationFrame so the browser has painted the layout before
    // we measure scroll offsets — otherwise the scroll lands short on
    // first paint.
    requestAnimationFrame(function () {
      result.scrollIntoView({ behavior: 'smooth', block: 'start' });
      result.focus({ preventScroll: true });
    });
  }

  // Subscribe to an AI-recommended feed. Mirrors the .js-catalog-add /
  // .js-add-feed handlers in public/feeds.js but posts to /api/feeds
  // (the manual-add endpoint) instead of /api/feeds/catalog/add (which
  // rejects URLs that aren't in the curated catalog). Inserts the new
  // row into the feeds table in-place + dims the AI suggestion row.
  //
  // Guarded with a one-shot flag so the document-level submit listener
  // only gets attached once even when init() fires on both
  // DOMContentLoaded AND turbo:load (which both run on initial page
  // load). Without the guard the listener attaches twice, two parallel
  // POST /api/feeds requests race, and the second one comes back as
  // "duplicate-url" because the first already created the subscription.
  var aiSubscribeWired = false;
  function wireAiSubscribe() {
    if (aiSubscribeWired) return;
    aiSubscribeWired = true;

    document.addEventListener('submit', function (e) {
      var form = e.target.closest('form.js-ai-subscribe');
      if (!form) return;
      e.preventDefault();
      // Re-query DOM nodes on every submit so a Turbo soft-navigation
      // back to /feeds doesn't leave us holding stale references.
      var feedsTable  = document.querySelector('.feeds-table');
      var feedsTbody  = feedsTable && feedsTable.tBodies[0];
      var feedCountEl = document.getElementById('feed-count');
      var btn = form.querySelector('button[type=submit]');
      var li  = form.closest('li.catalog-row');
      if (btn) {
        btn.disabled = true;
        btn.textContent = 'Subscribing…';
      }

      var data = new FormData(form);
      fetch('/api/feeds', { method: 'POST', body: data, credentials: 'same-origin' })
        .then(function (res) { return res.json().then(function (json) { return { ok: res.ok, status: res.status, data: json }; }); })
        .then(function (r) {
          if (r.ok && r.data.row_html) {
            if (feedsTable && feedsTable.style.display === 'none') feedsTable.style.display = '';
            if (feedsTbody) feedsTbody.insertAdjacentHTML('afterbegin', r.data.row_html);
            if (feedCountEl) {
              var n = parseInt(feedCountEl.textContent, 10) || 0;
              feedCountEl.textContent = (n + 1).toString();
            }
            // Mark the AI row as subscribed so a double-click is impossible.
            if (li) {
              li.classList.add('subscribed');
              if (form && form.parentNode) {
                var badge = document.createElement('span');
                badge.className = 'subscribed-badge';
                badge.textContent = '✓ Subscribed';
                form.parentNode.replaceChild(badge, form);
              }
            }
          } else {
            if (btn) {
              btn.disabled = false;
              btn.textContent = 'Subscribe';
            }
            var msg = (r.data && r.data.message) || 'Subscribe failed.';
            alert(msg);
          }
        })
        .catch(function (err) {
          if (btn) {
            btn.disabled = false;
            btn.textContent = 'Subscribe';
          }
          alert('Subscribe failed: ' + err.message);
        });
    });
  }

  function init() {
    wireSubmitIndicator();
    scrollResultIntoView();
    wireAiSubscribe();
  }

  document.addEventListener('DOMContentLoaded', init);
  document.addEventListener('turbo:load', init);
})();
