/* /triage form loading state. Triage::Claude.run is one synchronous
 * Claude API call that takes 10-30s on Sonnet 4.6 (longer on a big
 * unread queue). The page submits a normal HTML form and waits for
 * the route handler to render the result, so without this script the
 * "Generate triage now" / "Regenerate" / "Try again" buttons just sit
 * there with no feedback while the browser hangs on the POST.
 *
 * On submit we disable the button + swap its label so the user knows
 * the request is in flight. We do NOT preventDefault — the form still
 * submits normally and the existing route renders the result page. */
(function () {
  'use strict';

  var forms = document.querySelectorAll('form[action="/triage"]');
  if (!forms.length) return;

  forms.forEach(function (form) {
    form.addEventListener('submit', function () {
      var btn = form.querySelector('button[type="submit"]');
      if (!btn || btn.disabled) return;
      btn.dataset.originalText = btn.textContent.trim();
      btn.disabled = true;
      btn.classList.add('is-loading');
      btn.textContent = 'Generating… (10–30s)';
    });
  });
})();
