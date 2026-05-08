/* Bulk-actions controller for /articles.
 *
 * Each .news-item carries a leading <input.news-item-check data-uid=...>;
 * when ≥1 box is ticked the #bulk-toolbar slides into view. The toolbar
 * buttons POST {uids, action} to /api/articles/bulk and reload the page
 * on success so the read-state filters re-evaluate.
 *
 * Shift-click toggles a contiguous range from the last-clicked checkbox
 * to the just-clicked one, matching the convention every list-driven UI
 * uses (Gmail, Finder, GitHub).
 *
 * Init guard: this script re-executes on every Turbo body swap, but the
 * #bulk-toolbar lives inside the swapped <main>, so we re-bind every
 * time the script runs. No state survives navigation by design.
 */
(function () {
  'use strict';

  var list = document.querySelector('.news-list');
  if (!list) return;
  var toolbar = document.getElementById('bulk-toolbar');
  if (!toolbar) return;
  if (toolbar.dataset.bound === '1') return;
  toolbar.dataset.bound = '1';

  var countEl   = toolbar.querySelector('[data-bulk-count]');
  var clearBtn  = toolbar.querySelector('.bulk-toolbar-clear');
  var actionBtns = toolbar.querySelectorAll('[data-bulk-action]');
  var checkboxes = function () { return Array.from(list.querySelectorAll('.news-item-check')); };
  var lastClickedIndex = null;

  function selected() {
    return checkboxes().filter(function (cb) { return cb.checked; });
  }

  function paint() {
    var n = selected().length;
    countEl.textContent = String(n);
    toolbar.hidden = n === 0;
    list.classList.toggle('has-selection', n > 0);
    actionBtns.forEach(function (b) { b.disabled = n === 0; });
  }

  list.addEventListener('click', function (e) {
    var cb = e.target.closest('.news-item-check');
    if (!cb) return;
    // Shift-click: toggle every checkbox between the last-clicked and
    // this one to whatever this one is now. Matches Gmail / GitHub.
    var all = checkboxes();
    var idx = all.indexOf(cb);
    if (e.shiftKey && lastClickedIndex !== null && lastClickedIndex !== idx) {
      var lo = Math.min(lastClickedIndex, idx);
      var hi = Math.max(lastClickedIndex, idx);
      for (var i = lo; i <= hi; i++) all[i].checked = cb.checked;
    }
    lastClickedIndex = idx;
    paint();
  });

  clearBtn.addEventListener('click', function () {
    checkboxes().forEach(function (cb) { cb.checked = false; });
    lastClickedIndex = null;
    paint();
  });

  actionBtns.forEach(function (btn) {
    if (btn === clearBtn) return;
    btn.addEventListener('click', function () {
      var action = btn.dataset.bulkAction;
      var uids = selected().map(function (cb) { return cb.dataset.uid; });
      if (uids.length === 0) return;

      actionBtns.forEach(function (b) { b.disabled = true; });
      btn.classList.add('is-pending');

      fetch('/api/articles/bulk', {
        method: 'POST',
        credentials: 'same-origin',
        headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
        body: JSON.stringify({ uids: uids, action: action })
      })
        .then(function (r) {
          if (!r.ok) throw new Error('HTTP ' + r.status);
          return r.json();
        })
        .then(function () {
          // Reload so the active state-filter (unread / bookmarked / archived)
          // re-evaluates. With Turbo this is a fast XHR swap, not a full
          // page load; the audio in #global-player is preserved.
          if (window.Turbo && window.Turbo.visit) {
            window.Turbo.visit(window.location.pathname + window.location.search);
          } else {
            window.location.reload();
          }
        })
        .catch(function (err) {
          btn.classList.remove('is-pending');
          actionBtns.forEach(function (b) { b.disabled = false; });
          alert('Bulk action failed: ' + err.message);
        });
    });
  });

  paint();
})();
