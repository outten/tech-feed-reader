/* Inline 👍 / 👎 controller for /articles + /bookmarks rows.
 *
 * The same .news-row-feedback markup ships with a plain <form> per
 * button so the no-JS fallback still works (server returns a 302 to
 * `return_to`). With JS, we intercept the click, POST via fetch with
 * `Accept: application/json`, and toggle the button state in place —
 * no navigation, no scroll-to-top.
 *
 * Re-binds on `turbo:load` since Turbo swaps the list <main> on
 * navigation (filter chips, pagination, etc.). The data-feedback-bound
 * guard avoids double-binding when the same list element is preserved.
 */
(function () {
  'use strict';

  function init() {
    var lists = document.querySelectorAll('.news-list');
    lists.forEach(function (list) {
      if (list.dataset.feedbackBound === '1') return;
      list.dataset.feedbackBound = '1';
      list.addEventListener('click', onClick);
    });
  }

  function onClick(e) {
    var btn = e.target.closest('.feedback-row-btn');
    if (!btn) return;
    var form = btn.closest('form');
    var wrapper = btn.closest('.news-row-feedback');
    if (!form || !wrapper) return;

    e.preventDefault();

    var valueInput = form.querySelector('input[name="value"]');
    var body = new URLSearchParams();
    body.set('value', valueInput ? valueInput.value : '0');

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
      .then(function (data) {
        applyState(wrapper, parseInt(data.value, 10) || 0);
      })
      .catch(function (err) {
        alert('Could not save feedback: ' + err.message);
      })
      .finally(function () {
        btn.disabled = false;
      });
  }

  function applyState(wrapper, value) {
    var upBtn   = wrapper.querySelector('.feedback-row-btn[aria-label="Thumbs up"]');
    var downBtn = wrapper.querySelector('.feedback-row-btn[aria-label="Thumbs down"]');
    if (!upBtn || !downBtn) return;

    var upInput   = upBtn.closest('form').querySelector('input[name="value"]');
    var downInput = downBtn.closest('form').querySelector('input[name="value"]');

    upBtn.classList.toggle('is-on', value === 1);
    downBtn.classList.toggle('is-on', value === -1);
    wrapper.classList.toggle('feedback-set', value !== 0);

    upInput.value   = (value === 1)  ? '0' : '1';
    downInput.value = (value === -1) ? '0' : '-1';

    upBtn.setAttribute('title',
      value === 1 ? 'Clear the thumbs-up on this article'
                  : 'Thumbs up — boost articles like this one in the For-You sort');
    downBtn.setAttribute('title',
      value === -1 ? 'Clear the thumbs-down on this article'
                   : 'Thumbs down — demote articles like this one in the For-You sort');
  }

  init();
  document.addEventListener('turbo:load', init);
})();
