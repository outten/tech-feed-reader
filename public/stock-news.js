/* Cold-start filler for the "Recent news" section on /stocks/:symbol.
 *
 * When a symbol's feed has no cached articles yet, the server renders
 * #stock-news with a data-stock-news-pending="SYMBOL" attribute and
 * enqueues a background refresh. This polls GET /stocks/:symbol/news a
 * handful of times and swaps the section in as soon as articles land —
 * no page reload. Once populated (no pending attr) it stops.
 *
 * Same init/turbo:load pattern as stock-follow.js. Element-level
 * dataset sentinel prevents double polling when both the initial run
 * and turbo:load fire.
 */
(function () {
  'use strict';

  var MAX_ATTEMPTS = 8;
  var INTERVAL_MS  = 2500;

  function init() {
    var el = document.getElementById('stock-news');
    if (!el) return;
    var symbol = el.getAttribute('data-stock-news-pending');
    if (!symbol) return;                       // already has news
    if (el.dataset.pollBound === '1') return;  // already polling
    el.dataset.pollBound = '1';
    poll(symbol, 0);
  }

  function poll(symbol, attempt) {
    if (attempt >= MAX_ATTEMPTS) return;

    fetch('/stocks/' + encodeURIComponent(symbol) + '/news', {
      credentials: 'same-origin',
      headers: { 'X-Requested-With': 'fetch' }
    })
      .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.text(); })
      .then(function (html) {
        var cur = document.getElementById('stock-news');
        if (!cur) return;
        var tmp = document.createElement('div');
        tmp.innerHTML = html.trim();
        var next = tmp.querySelector('#stock-news');
        if (!next) return;

        if (!next.hasAttribute('data-stock-news-pending')) {
          cur.replaceWith(next);               // populated — swap in and stop
          return;
        }
        retry(symbol, attempt);                // still cold — keep waiting
      })
      .catch(function () { retry(symbol, attempt); });
  }

  function retry(symbol, attempt) {
    window.setTimeout(function () { poll(symbol, attempt + 1); }, INTERVAL_MS);
  }

  init();
  document.addEventListener('turbo:load', init);
})();
