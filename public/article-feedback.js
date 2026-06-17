/* Inline 👍 / 👎 controller for article feedback. Two surfaces:
 *   1. /articles + /bookmarks list rows (.news-list / .news-row-feedback).
 *   2. The article detail page (.js-article-feedback forms) — STUFF #99.
 *
 * Both ship plain <form>s so the no-JS fallback still works (server
 * returns 302 / re-renders without JS). With JS we intercept, POST via
 * fetch with `Accept: application/json`, and toggle button state in
 * place — no navigation, no scroll-to-top, no full-page reload.
 *
 * Re-binds on `turbo:load` since Turbo swaps the <body>/list on
 * navigation. The dataset-bound guards avoid double-binding.
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
    initDetail();
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

  // --- Article detail page (#99) -------------------------------------
  // The detail page renders two <form.js-article-feedback> (data-feedback
  // up/down) that full-reload without JS. Intercept + re-render both
  // buttons from the JSON `value` (the toggle target of each depends on
  // the current state). Config mirrors views/article.erb exactly.
  var DETAIL = {
    up: {
      active: 1, on: '0', off: '1', cls: 'feedback-on-up',
      labelOn: '👍 Boosted', labelOff: '👍',
      titleOn: 'Clear the thumbs-up',
      titleOff: 'Thumbs up — the For-You ranker will boost articles like this one'
    },
    down: {
      active: -1, on: '0', off: '-1', cls: 'feedback-on-down',
      labelOn: '👎 Demoted', labelOff: '👎',
      titleOn: 'Clear the thumbs-down',
      titleOff: 'Thumbs down — the For-You ranker will demote articles like this one'
    }
  };

  function initDetail() {
    if (document.body.dataset.articleDetailFeedbackBound === '1') return;
    document.body.dataset.articleDetailFeedbackBound = '1';
    document.body.addEventListener('submit', onDetailSubmit, true);
  }

  function onDetailSubmit(e) {
    var form = e.target;
    if (!form || !form.matches || !form.matches('form.js-article-feedback')) return;
    e.preventDefault();

    var btn = form.querySelector('button[type="submit"]');
    var valueInput = form.querySelector('input[name="value"]');
    var body = new URLSearchParams();
    body.set('value', valueInput ? valueInput.value : '0');
    if (btn) btn.disabled = true;

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
      .then(function (data) { applyDetailState(parseInt(data.value, 10) || 0); })
      .catch(function (err) {
        console.warn('[article-feedback] detail AJAX failed, falling back to submit', err);
        form.submit();
      })
      .finally(function () { if (btn) btn.disabled = false; });
  }

  function applyDetailState(value) {
    renderDetailButton('up', value === DETAIL.up.active);
    renderDetailButton('down', value === DETAIL.down.active);
  }

  function renderDetailButton(which, active) {
    var cfg = DETAIL[which];
    var form = document.querySelector('form.js-article-feedback[data-feedback="' + which + '"]');
    if (!form) return;
    var input = form.querySelector('input[name="value"]');
    var btn = form.querySelector('button[type="submit"]');
    if (input) input.value = active ? cfg.on : cfg.off;
    if (btn) {
      btn.classList.toggle(cfg.cls, active);
      btn.textContent = active ? cfg.labelOn : cfg.labelOff;
      btn.title = active ? cfg.titleOn : cfg.titleOff;
    }
  }

  init();
  document.addEventListener('turbo:load', init);
})();
