/* Header refresh button — every page renders this in layout.erb. The
 * non-JS form posts to /refresh/all, which redirects to /feeds with a
 * notice. With JS we hijack the submit, call the JSON endpoint, and
 * show a transient toast in #header-flash so the user keeps the page
 * they were on. */
(function () {
  'use strict';

  var form = document.querySelector('form.js-header-refresh');
  if (!form) return;
  var flash = document.getElementById('header-flash');

  function toast(message, kind) {
    if (!flash) return;
    var div = document.createElement('div');
    div.className = 'header-toast' + (kind === 'error' ? ' error' : '');
    div.textContent = message;
    flash.replaceChildren(div);
    clearTimeout(toast._timer);
    toast._timer = setTimeout(function () {
      if (flash.firstChild === div) flash.replaceChildren();
    }, 3500);
  }

  form.addEventListener('submit', function (e) {
    e.preventDefault();
    var btn = form.querySelector('button[type="submit"]');
    if (btn) btn.disabled = true;

    fetch('/api/refresh/all', {
      method: 'POST',
      headers: { 'Accept': 'application/json' }
    }).then(function (res) {
      return res.json().then(function (data) { return { ok: res.ok, data: data }; })
                       .catch(function () { return { ok: res.ok, data: {} }; });
    }).then(function (r) {
      if (btn) btn.disabled = false;
      if (r.ok) {
        var n = r.data.queued || 0;
        toast('Queued ' + n + ' feed' + (n === 1 ? '' : 's') + ' for refresh.');
      } else {
        toast(r.data.message || 'Refresh failed.', 'error');
      }
    });
  });
})();
