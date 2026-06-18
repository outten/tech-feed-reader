/* Lazy "Read next" card (change: speed-up-article-load).
 *
 * The article page ships a `.read-next-sentinel` plus an empty container
 * with `data-read-next-url`. When the sentinel nears the viewport we fetch
 * the card fragment from that URL (which computes the personalized
 * ForYou.next_after suggestion server-side) and swap it in. Deferring it
 * keeps the cold-cache ranking off the article's critical render path, and
 * skips it entirely for readers who never scroll to the bottom.
 *
 * Same init / turbo:load pattern as the other layout scripts; the
 * container's dataset sentinel prevents a double fetch.
 */
(function () {
  'use strict';

  function load(container, url) {
    fetch(url, { credentials: 'same-origin', headers: { 'X-Requested-With': 'fetch' } })
      .then(function (r) { return r.ok ? r.text() : ''; })
      .then(function (html) {
        if (!html.trim()) return;            // no suggestion — leave placeholder empty
        var tmp = document.createElement('div');
        tmp.innerHTML = html.trim();
        var card = tmp.querySelector('.read-next-card');
        if (card && container.isConnected) container.replaceWith(card);
      })
      .catch(function () { /* card is optional — never disrupt the page */ });
  }

  function init() {
    var container = document.querySelector('[data-read-next-url]');
    if (!container || container.dataset.rnBound === '1') return;
    container.dataset.rnBound = '1';

    var url      = container.getAttribute('data-read-next-url');
    var sentinel = document.querySelector('.read-next-sentinel');

    if (sentinel && 'IntersectionObserver' in window) {
      var io = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) {
          if (e.isIntersecting) { io.disconnect(); load(container, url); }
        });
      }, { rootMargin: '0px 0px 200px 0px' });   // prefetch a little before it's visible
      io.observe(sentinel);
    } else {
      load(container, url);                       // no IO support — just load it
    }
  }

  init();
  document.addEventListener('turbo:load', init);
})();
