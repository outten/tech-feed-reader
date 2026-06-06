/* STUFF #85 — AJAX follow/unfollow for stock symbols.
 *
 * Same pattern as sports-follow.js. The .js-stock-follow-form class
 * is used on /stocks (search + indices) and /stocks/:symbol (detail).
 * Server returns {ok, symbol, followed} when Accept: application/json;
 * we toggle the button state in-place and rewrite the form's action.
 */
(function () {
  'use strict';

  function init() {
    if (document.body.dataset.stockFollowBound === '1') return;
    document.body.dataset.stockFollowBound = '1';
    document.body.addEventListener('submit', onSubmit, true);
  }

  function onSubmit(e) {
    var form = e.target;
    if (!form || !form.matches || !form.matches('form.js-stock-follow-form')) return;
    e.preventDefault();
    var btn = form.querySelector('button[type="submit"]');
    submit(form, btn);
  }

  function submit(form, btn) {
    var symbolInput = form.querySelector('input[name="symbol"]');
    var nameInput   = form.querySelector('input[name="name"]');
    var body = new URLSearchParams();
    body.set('symbol', symbolInput ? symbolInput.value : '');
    if (nameInput && nameInput.value) body.set('name', nameInput.value);

    btn.disabled = true;

    fetch(form.getAttribute('action'), {
      method: 'POST',
      credentials: 'same-origin',
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded'
      },
      body: body.toString()
    })
      .then(function (r) {
        if (!r.ok) throw new Error('HTTP ' + r.status);
        return r.json();
      })
      .then(function (data) { applyState(form, btn, data); })
      .catch(function (err) {
        console.warn('[stock-follow] AJAX failed, falling back to form submit', err);
        form.submit();
      })
      .finally(function () { btn.disabled = false; });
  }

  function applyState(form, btn, data) {
    var followed = !!data.followed;

    // Flip the form's action so the next click does the opposite.
    form.action = '/stocks/' + (followed ? 'unfollow' : 'follow');

    // Toggle button classes + text.
    btn.classList.toggle('is-following', followed);
    btn.classList.toggle('btn-primary', !followed);
    btn.classList.toggle('btn-secondary', followed);

    var followLabel    = btn.dataset.followLabel    || '+ Follow';
    var followingLabel = btn.dataset.followingLabel || '✓ Following';
    btn.textContent = followed ? followingLabel : followLabel;
  }

  init();
  document.addEventListener('turbo:load', init);
})();
