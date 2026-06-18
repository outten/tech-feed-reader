/* Lazy fragment loader (changes: speed-up-article-load, async-related-articles).
 *
 * Any element with `data-fragment-url` is a placeholder. When its sentinel
 * (the element named by `data-fragment-sentinel`, or the placeholder itself)
 * nears the viewport, we fetch that URL and replace the placeholder with the
 * returned fragment's root element. An empty response leaves the placeholder
 * in place (invisible). Used to keep the article page's expensive server-side
 * panels — the personalized "Read next" card and the "Related" FTS panel —
 * off the critical render path, and to skip them for readers who never scroll
 * that far.
 *
 * Same init / turbo:load pattern as the other layout scripts; a per-element
 * dataset sentinel prevents a double fetch.
 */
(function () {
  'use strict';

  function load(placeholder) {
    var url = placeholder.getAttribute('data-fragment-url');
    fetch(url, { credentials: 'same-origin', headers: { 'X-Requested-With': 'fetch' } })
      .then(function (r) { return r.ok ? r.text() : ''; })
      .then(function (html) {
        if (!html.trim() || !placeholder.isConnected) return;  // nothing to show / gone
        var tmp = document.createElement('div');
        tmp.innerHTML = html.trim();
        var node = tmp.firstElementChild;
        if (node) placeholder.replaceWith(node);
      })
      .catch(function () { /* fragments are optional — never disrupt the page */ });
  }

  function arm(placeholder) {
    if (placeholder.dataset.fragBound === '1') return;
    placeholder.dataset.fragBound = '1';

    var sel      = placeholder.getAttribute('data-fragment-sentinel');
    var sentinel = sel ? document.querySelector(sel) : placeholder;

    if (sentinel && 'IntersectionObserver' in window) {
      var io = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) {
          if (e.isIntersecting) { io.disconnect(); load(placeholder); }
        });
      }, { rootMargin: '0px 0px 200px 0px' });   // fetch a little before it's visible
      io.observe(sentinel);
    } else {
      load(placeholder);                          // no IO support — just load it
    }
  }

  function init() {
    document.querySelectorAll('[data-fragment-url]').forEach(arm);
  }

  init();
  document.addEventListener('turbo:load', init);
})();
