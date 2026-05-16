/* /article/:uid "Summarize with Claude" loading state. Same pattern
 * as digest-summarize-form.js — Summarizer::Claude.summarize_article
 * is a 5-15s synchronous API call, and without feedback the button
 * looks dead. On submit we disable the button + swap the label so the
 * user knows the request is in flight. We do NOT preventDefault — the
 * form still submits normally and the route renders the result page. */
(function () {
  'use strict';

  var forms = document.querySelectorAll('form.js-article-summarize');
  if (!forms.length) return;

  forms.forEach(function (form) {
    form.addEventListener('submit', function () {
      var btn = form.querySelector('button[type="submit"]');
      if (!btn || btn.disabled) return;
      btn.dataset.originalText = btn.textContent.trim();
      btn.disabled = true;
      btn.classList.add('is-loading');
      btn.textContent = 'Summarizing… (5–15s)';
    });
  });
})();
