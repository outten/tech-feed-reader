// STUFF #27 — client-side filter for the two long lists on /feeds:
//   1. Subscribed feeds table (target="feeds-table")
//   2. Catalog browse list   (target="catalog")
//
// Each filter bar carries an <input type="search"> + a row of topic
// chips. The same module wires both. Rows expose data-topic and
// data-search attributes (lowercased title/url/blurb concatenation);
// the filter just toggles visibility — no server round-trip.
//
// Catalog-only: when every row beneath a `<h4 class="catalog-category">`
// is hidden, we hide the heading too. Plus a small "showing N of M"
// counter on the right side of each bar so the user can tell the
// filter actually narrowed anything.

(function () {
  // Match any <tr data-feed-id> for the subscribed table; any
  // <li class="catalog-row"> for the catalog.
  var ROW_SELECTORS = {
    'feeds-table': 'tbody tr[data-feed-id]',
    'catalog':     'li.catalog-row'
  };

  function rowsFor(target) {
    if (target === 'feeds-table') {
      var table = document.querySelector('table.feeds-table');
      return table ? Array.prototype.slice.call(table.querySelectorAll(ROW_SELECTORS[target])) : [];
    }
    var section = document.getElementById('discover-catalog');
    return section ? Array.prototype.slice.call(section.querySelectorAll(ROW_SELECTORS[target])) : [];
  }

  // Hide category <h4> when all of its sibling list rows are hidden.
  // Walks forward from each catalog-category heading through the
  // immediately following <ul> and checks every row's display.
  function syncCategoryHeadings() {
    var headings = document.querySelectorAll('#discover-catalog h4.catalog-category');
    headings.forEach(function (h) {
      var ul = h.nextElementSibling;
      while (ul && ul.tagName !== 'UL') ul = ul.nextElementSibling;
      if (!ul) return;
      var rows = ul.querySelectorAll('li.catalog-row');
      var anyVisible = false;
      rows.forEach(function (r) { if (r.style.display !== 'none') anyVisible = true; });
      h.style.display = anyVisible ? '' : 'none';
      ul.style.display = anyVisible ? '' : 'none';
    });
  }

  function applyFilter(bar) {
    var target  = bar.dataset.target;
    var input   = bar.querySelector('.feeds-filter-search');
    var chip    = bar.querySelector('.feeds-filter-chip.is-active');
    var counter = bar.querySelector('.feeds-filter-count');
    var rows    = rowsFor(target);
    if (rows.length === 0) return;

    var query = (input && input.value || '').trim().toLowerCase();
    var topic = (chip && chip.dataset.topic || '');

    var shown = 0;
    rows.forEach(function (row) {
      var match =
        (topic === '' || (row.dataset.topic || '') === topic) &&
        (query === '' || (row.dataset.search || '').indexOf(query) !== -1);
      row.style.display = match ? '' : 'none';
      if (match) shown += 1;
    });

    if (target === 'catalog') syncCategoryHeadings();

    if (counter) {
      counter.textContent = (shown === rows.length) ?
        '' :
        ('showing ' + shown + ' of ' + rows.length);
    }
  }

  function wireBar(bar) {
    var input = bar.querySelector('.feeds-filter-search');
    var chips = bar.querySelectorAll('.feeds-filter-chip');
    if (input) {
      input.addEventListener('input',  function () { applyFilter(bar); });
    }
    chips.forEach(function (c) {
      c.addEventListener('click', function () {
        chips.forEach(function (other) { other.classList.remove('is-active'); });
        c.classList.add('is-active');
        applyFilter(bar);
      });
    });
  }

  function init() {
    document.querySelectorAll('.feeds-filter-bar').forEach(wireBar);
  }

  document.addEventListener('DOMContentLoaded', init);
  document.addEventListener('turbo:load', init);
})();
