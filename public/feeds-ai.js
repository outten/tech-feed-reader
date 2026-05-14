// STUFF.md #23 polish — UX wiring for the Ask-AI feed recommender.
//
// 1. On form submit, flip the inline "AI is thinking…" indicator on so the
//    user sees that the request is in flight (the server round-trip is
//    synchronous and takes 1–4s — without this the page just hangs).
// 2. On page load, if a result block is present from a prior submit,
//    scroll it into view + focus it so the response is impossible to miss.
//
// Re-runs on `turbo:load` so it survives soft navigation as well as a
// full reload.

(function () {
  function wireSubmitIndicator() {
    var form = document.querySelector('.js-ai-recommend');
    if (!form) return;
    var indicator = form.querySelector('.ai-thinking');
    var button    = form.querySelector('button[type=submit]');
    form.addEventListener('submit', function () {
      if (indicator) indicator.hidden = false;
      if (button) {
        button.disabled = true;
        button.dataset.originalLabel = button.textContent;
        button.textContent = 'Thinking…';
      }
    });
  }

  function scrollResultIntoView() {
    var result = document.getElementById('ai-recommend-result');
    if (!result) return;
    // requestAnimationFrame so the browser has painted the layout before
    // we measure scroll offsets — otherwise the scroll lands short on
    // first paint.
    requestAnimationFrame(function () {
      result.scrollIntoView({ behavior: 'smooth', block: 'start' });
      result.focus({ preventScroll: true });
    });
  }

  function init() {
    wireSubmitIndicator();
    scrollResultIntoView();
  }

  document.addEventListener('DOMContentLoaded', init);
  document.addEventListener('turbo:load', init);
})();
