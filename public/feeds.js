/* Feeds page — AJAX hooks for add / remove / catalog-add / refresh.
 *
 * Each form on the page keeps its `action=` so a non-JS browser still
 * works (the action POSTs to the redirect-style route, which lands on
 * /feeds with a notice). When JS runs we hijack the submit, call the
 * matching /api/* JSON endpoint, and update the DOM in place — the
 * page never reloads, the user keeps their scroll position.
 */
(function () {
  'use strict';

  var flash = document.getElementById('flash-mount');
  var table = document.querySelector('table.feeds-table');
  var tbody = table ? table.querySelector('tbody') : null;
  var countEl = document.getElementById('feed-count');

  function showFlash(message, kind) {
    if (!flash) return;
    var div = document.createElement('div');
    div.className = kind === 'error' ? 'error' : 'notice';
    div.textContent = message;
    flash.replaceChildren(div);
    clearTimeout(showFlash._timer);
    showFlash._timer = setTimeout(function () {
      if (flash.firstChild === div) flash.replaceChildren();
    }, 4000);
  }

  function bumpCount(delta) {
    if (!countEl) return;
    var n = parseInt(countEl.textContent, 10) || 0;
    countEl.textContent = String(Math.max(0, n + delta));
  }

  function ensureTableVisible() {
    if (table) table.style.display = '';
  }

  function postForm(url, form, method) {
    var fd = form ? new FormData(form) : null;
    var body = fd ? new URLSearchParams(fd) : null;
    return fetch(url, {
      method: method || 'POST',
      headers: { 'Accept': 'application/json' },
      body: body
    }).then(function (res) {
      return res.json().then(function (data) {
        return { ok: res.ok, status: res.status, data: data };
      }).catch(function () {
        return { ok: res.ok, status: res.status, data: {} };
      });
    });
  }

  /* ---- Add a feed (top-of-page form) -------------------------------- */
  var addForm = document.querySelector('form.js-add-feed');
  if (addForm) {
    addForm.addEventListener('submit', function (e) {
      e.preventDefault();
      var btn = addForm.querySelector('button[type="submit"]');
      if (btn) btn.disabled = true;
      postForm('/api/feeds', addForm).then(function (r) {
        if (btn) btn.disabled = false;
        if (r.ok && r.data.row_html) {
          ensureTableVisible();
          if (tbody) tbody.insertAdjacentHTML('afterbegin', r.data.row_html);
          bumpCount(1);
          addForm.reset();
          showFlash('Feed added.');
        } else {
          showFlash(r.data.message || 'Failed to add feed.', 'error');
        }
      });
    });
  }

  /* ---- Remove a feed (per-row, delegated since rows are dynamic) ---- */
  document.addEventListener('submit', function (e) {
    var form = e.target.closest('form.js-remove-feed');
    if (!form) return;
    e.preventDefault();
    if (!confirm('Remove this feed and all its articles?')) return;

    var row = form.closest('tr');
    var id  = row && row.dataset.feedId;
    if (!id) {
      // Fallback — pull from the form action if the row didn't carry it
      var m = form.action.match(/\/feeds\/(\d+)/);
      id = m && m[1];
    }
    if (!id) return;

    postForm('/api/feeds/' + id, null, 'DELETE').then(function (r) {
      if (r.ok) {
        if (row) row.remove();
        bumpCount(-1);
        // Mark the catalog item (if any) as no-longer-subscribed so the
        // user can re-add it. Match by URL stored in the row.
        var url = row ? row.querySelector('td a') && row.querySelector('td a').getAttribute('href') : null;
        if (url) {
          var cat = document.querySelector('.catalog-row[data-catalog-url="' + url.replace(/"/g, '\\"') + '"]');
          if (cat) restoreCatalogAddButton(cat, url);
        }
        showFlash('Feed removed.');
      } else {
        showFlash(r.data.message || 'Failed to remove feed.', 'error');
      }
    });
  });

  /* ---- Catalog "+ Add" -------------------------------------------- */
  document.addEventListener('submit', function (e) {
    var form = e.target.closest('form.js-catalog-add');
    if (!form) return;
    e.preventDefault();
    var li = form.closest('li.catalog-row');
    var btn = form.querySelector('button[type="submit"]');
    if (btn) btn.disabled = true;

    postForm('/api/feeds/catalog/add', form).then(function (r) {
      if (btn) btn.disabled = false;
      if (r.ok && r.data.row_html) {
        ensureTableVisible();
        if (tbody) tbody.insertAdjacentHTML('afterbegin', r.data.row_html);
        if (r.data.status === 'added') {
          bumpCount(1);
          showFlash('Added "' + (r.data.feed && r.data.feed.title || 'feed') + '" from the catalog.');
        } else {
          showFlash('"' + (r.data.feed && r.data.feed.title || 'feed') + '" is already subscribed.');
        }
        markCatalogSubscribed(li);
      } else {
        showFlash(r.data.message || 'Failed to add from catalog.', 'error');
      }
    });
  });

  function markCatalogSubscribed(li) {
    if (!li) return;
    var form = li.querySelector('form.js-catalog-add');
    if (form) form.remove();
    if (!li.querySelector('.subscribed-badge')) {
      var badge = document.createElement('span');
      badge.className = 'badge subscribed-badge';
      badge.textContent = '✓ Subscribed';
      li.appendChild(badge);
    }
    li.classList.add('subscribed');
  }

  function restoreCatalogAddButton(li, url) {
    var existingBadge = li.querySelector('.subscribed-badge');
    if (existingBadge) existingBadge.remove();
    li.classList.remove('subscribed');
    if (li.querySelector('form.js-catalog-add')) return;
    var form = document.createElement('form');
    form.method = 'post';
    form.action = '/feeds/catalog/add';
    form.className = 'js-catalog-add';
    var input = document.createElement('input');
    input.type = 'hidden';
    input.name = 'url';
    input.value = url;
    form.appendChild(input);
    var btn = document.createElement('button');
    btn.type = 'submit';
    btn.className = 'btn-primary';
    btn.textContent = '+ Add';
    form.appendChild(btn);
    li.appendChild(form);
  }

  /* ---- Per-row Refresh ------------------------------------------- */
  document.addEventListener('submit', function (e) {
    var form = e.target.closest('form.js-refresh-feed');
    if (!form) return;
    e.preventDefault();
    var row = form.closest('tr');
    var id  = row && row.dataset.feedId;
    if (!id) {
      var m = form.action.match(/\/admin\/refresh\/(\d+)/);
      id = m && m[1];
    }
    if (!id) return;

    var btn = form.querySelector('button[type="submit"]');
    if (btn) { btn.disabled = true; btn.textContent = 'Queued'; }
    postForm('/api/admin/refresh/' + id).then(function (r) {
      if (btn) { btn.disabled = false; btn.textContent = 'Refresh'; }
      if (r.ok) {
        showFlash('Queued for refresh. Watch /admin/sidekiq for progress.');
      } else {
        showFlash(r.data.message || 'Failed to queue refresh.', 'error');
      }
    });
  });

  /* ---- "Refresh all" (page-header button) ------------------------ */
  var refreshAll = document.querySelector('form.js-refresh-all');
  if (refreshAll) {
    refreshAll.addEventListener('submit', function (e) {
      e.preventDefault();
      var btn = refreshAll.querySelector('button[type="submit"]');
      if (btn) btn.disabled = true;
      postForm('/api/admin/refresh/all').then(function (r) {
        if (btn) btn.disabled = false;
        if (r.ok) {
          showFlash('Queued ' + r.data.queued + ' feed' + (r.data.queued === 1 ? '' : 's') + ' for refresh.');
        } else {
          showFlash(r.data.message || 'Failed to queue refresh-all.', 'error');
        }
      });
    });
  }
})();
