/* Random nature-photo backgrounds. Hot-links to Picsum (lorem-picsum.com)
 * for a curated set of image IDs that are scenic / nature-themed.
 * Picks fresh on every page load — with Turbo, that means a new image
 * on every navigation. After the pick, fetches /id/<id>/info from
 * Picsum to get the original photographer's name + Unsplash link, and
 * renders an attribution line in the footer. Picsum/Unsplash don't
 * require attribution but it's polite, and the footer slot is small.
 *
 * The actual styling lives in style.css. This script just sets the
 * --page-bg CSS variable on the documentElement; the body's
 * background-image stack reads that variable.
 *
 * Shuffle hook: any element with [data-bg-shuffle] becomes a "pick a
 * new image right now" link. Used by the footer link.
 */
(function () {
  'use strict';

  // Bundled curated Picsum IDs (nature / scenic). The layout normally
  // overrides this via window.PAGE_BACKGROUND_IDS — that comes from
  // BackgroundPool.ids in the Ruby side and is editable from
  // /admin/backgrounds. The bundled set is the offline / no-script
  // fallback if the inline script doesn't paint a value first.
  var FALLBACK_IDS = [10, 15, 28, 29, 1015, 1018, 1019, 1037, 1043, 1044, 1059];
  var IDS = (Array.isArray(window.PAGE_BACKGROUND_IDS) && window.PAGE_BACKGROUND_IDS.length > 0)
              ? window.PAGE_BACKGROUND_IDS
              : FALLBACK_IDS;
  var W = 2400;
  var H = 1600;

  function urlFor(id) {
    return 'https://picsum.photos/id/' + id + '/' + W + '/' + H;
  }

  function pick() {
    var id = IDS[Math.floor(Math.random() * IDS.length)];
    return { id: id, url: urlFor(id) };
  }

  function apply(url) {
    document.documentElement.style.setProperty('--page-bg', 'url("' + url + '")');
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c];
    });
  }

  // Picsum's /id/<id>/info endpoint returns {author, url, ...}; we use
  // those to render "Photo by Bob Lake on Unsplash" in the footer.
  // Network failure is silent — attribution stays empty rather than
  // breaking the page.
  function paintAttribution(id) {
    var el = document.querySelector('[data-bg-attribution]');
    if (!el) return;
    el.innerHTML = '';  // clear any prior pick's attribution while the fetch is in flight
    fetch('https://picsum.photos/id/' + id + '/info', { credentials: 'omit' })
      .then(function (r) { return r.ok ? r.json() : null; })
      .catch(function () { return null; })
      .then(function (info) {
        if (!info || !info.author) return;
        var author = escapeHtml(info.author);
        var href = escapeHtml(info.url || ('https://picsum.photos/id/' + id));
        el.innerHTML =
          'Photo by <a href="' + href + '" target="_blank" rel="noopener">' + author + '</a>' +
          ' on <a href="https://unsplash.com" target="_blank" rel="noopener">Unsplash</a>';
      });
  }

  function pickApplyAttribute() {
    var p = pick();
    apply(p.url);
    paintAttribution(p.id);
  }

  // No init guard — picks fresh on every script execution, including
  // Turbo body swaps. That's the per-page-random behaviour the user
  // asked for.
  pickApplyAttribute();

  // Shuffle button: re-pick + re-attribute. Re-bind on every Turbo
  // swap since the button lives inside <main> (well, inside the
  // footer of layout.erb — body-level, so the `data-bound` guard
  // keeps things clean).
  var btn = document.querySelector('[data-bg-shuffle]');
  if (btn && btn.dataset.bound !== '1') {
    btn.dataset.bound = '1';
    btn.addEventListener('click', function (e) {
      e.preventDefault();
      pickApplyAttribute();
    });
  }
})();
