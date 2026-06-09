/* AJAX subscribe/unsubscribe for source-specific pages (/npr, /pbs).
 *
 * Guards itself with a .my-feeds-section check so it doesn't
 * conflict with feeds.js on /feeds (which also uses js-catalog-add).
 *
 * subscribe  — POST /api/feeds/catalog/add → mark row subscribed,
 *              insert row into "My X" section, show section if hidden
 * unsubscribe — DELETE /api/feeds/:id → remove row from "My X",
 *              hide section if now empty, restore catalog "+ Add" button
 */
(function () {
  'use strict';

  var flash = document.getElementById('flash-mount');

  function onSourcePage() {
    return !!document.querySelector('.my-feeds-section');
  }

  function showFlash(msg, kind) {
    if (!flash) return;
    var div = document.createElement('div');
    div.className = kind === 'error' ? 'error' : 'notice';
    div.textContent = msg;
    flash.replaceChildren(div);
    clearTimeout(showFlash._t);
    showFlash._t = setTimeout(function () {
      if (flash.firstChild === div) flash.replaceChildren();
    }, 4000);
  }

  function post(url, form, method) {
    var body = form ? new URLSearchParams(new FormData(form)) : null;
    return fetch(url, {
      method: method || 'POST',
      headers: { Accept: 'application/json' },
      body: body
    }).then(function (res) {
      return res.json().then(function (d) {
        return { ok: res.ok, data: d };
      }).catch(function () {
        return { ok: res.ok, data: {} };
      });
    });
  }

  function esc(str) {
    return String(str || '')
      .replace(/&/g, '&amp;').replace(/</g, '&lt;')
      .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  /* ── Subscribe (catalog "+ Add") ─────────────────────────────────── */
  document.addEventListener('submit', function (e) {
    var form = e.target.closest('form.js-catalog-add');
    if (!form || !onSourcePage()) return;
    e.preventDefault();

    var li  = form.closest('li.catalog-row');
    var btn = form.querySelector('button');
    if (btn) btn.disabled = true;

    post('/api/feeds/catalog/add', form).then(function (r) {
      if (btn) btn.disabled = false;
      if (!r.ok || !r.data.feed) {
        showFlash(r.data.message || 'Failed to subscribe.', 'error');
        return;
      }
      var feed = r.data.feed;
      markCatalogSubscribed(li);
      addToMySection(feed);
      showFlash('Subscribed to “' + (feed.title || feed.url) + '”.');
    });
  });

  /* ── Unsubscribe ("Remove" button in My X section) ───────────────── */
  document.addEventListener('submit', function (e) {
    var form = e.target.closest('form.js-remove-feed');
    if (!form || !onSourcePage()) return;
    e.preventDefault();

    var li  = form.closest('li.catalog-row');
    var url = li && li.dataset.catalogUrl;
    var m   = form.action.match(/\/feeds\/(\d+)/);
    var id  = m && m[1];
    if (!id) return;

    var btn = form.querySelector('button');
    if (btn) btn.disabled = true;

    post('/api/feeds/' + id, null, 'DELETE').then(function (r) {
      if (!r.ok) {
        if (btn) btn.disabled = false;
        showFlash(r.data.message || 'Failed to unsubscribe.', 'error');
        return;
      }
      if (li) li.remove();
      syncMySectionVisibility();
      if (url) {
        var catRow = document.querySelector(
          '.catalog-section .catalog-row[data-catalog-url="' + url.replace(/"/g, '\\"') + '"]'
        );
        if (catRow) restoreCatalogRow(catRow, url);
      }
      showFlash('Unsubscribed.');
    });
  });

  /* ── DOM helpers ──────────────────────────────────────────────────── */

  function markCatalogSubscribed(li) {
    if (!li) return;
    var f = li.querySelector('form.js-catalog-add');
    if (f) f.remove();
    if (!li.querySelector('.subscribed-badge')) {
      var badge = document.createElement('span');
      badge.className = 'badge subscribed-badge';
      badge.title = 'Already in your subscriptions';
      badge.textContent = '✓ Subscribed';
      li.appendChild(badge);
    }
    li.classList.add('subscribed');
  }

  function restoreCatalogRow(li, url) {
    var badge = li.querySelector('.subscribed-badge');
    if (badge) badge.remove();
    li.classList.remove('subscribed');
    if (li.querySelector('form.js-catalog-add')) return;
    var form  = document.createElement('form');
    form.method = 'post';
    form.action = '/feeds/catalog/add';
    form.className = 'js-catalog-add';
    var inp = document.createElement('input');
    inp.type = 'hidden'; inp.name = 'url'; inp.value = url;
    form.appendChild(inp);
    var btn = document.createElement('button');
    btn.type = 'submit'; btn.className = 'btn-primary'; btn.textContent = '+ Add';
    form.appendChild(btn);
    li.appendChild(form);
  }

  function addToMySection(feed) {
    var section = document.querySelector('.my-feeds-section');
    if (!section) return;
    section.style.display = '';

    var ul = section.querySelector('ul.catalog-list');
    if (!ul) {
      ul = document.createElement('ul');
      ul.className = 'catalog-list';
      section.appendChild(ul);
    }

    var li = document.createElement('li');
    li.className = 'catalog-row';
    li.dataset.catalogUrl = feed.url;
    li.innerHTML =
      '<div class="catalog-meta">' +
        '<span class="catalog-title">' + esc(feed.title || feed.url) + '</span>' +
        '<span class="muted catalog-url">' + esc(feed.url) + '</span>' +
      '</div>' +
      '<form method="post" action="/feeds/' + feed.id + '/delete" class="js-remove-feed">' +
        '<button type="submit" class="danger" title="Unsubscribe from this feed">Remove</button>' +
      '</form>';
    ul.appendChild(li);

    var countEl = section.querySelector('.my-feeds-count');
    if (countEl) countEl.textContent = String((parseInt(countEl.textContent, 10) || 0) + 1);
  }

  function syncMySectionVisibility() {
    var section = document.querySelector('.my-feeds-section');
    if (!section) return;
    var ul    = section.querySelector('ul.catalog-list');
    var count = ul ? ul.querySelectorAll('li').length : 0;
    if (count === 0) section.style.display = 'none';
    var countEl = section.querySelector('.my-feeds-count');
    if (countEl) countEl.textContent = String(count);
  }
})();
