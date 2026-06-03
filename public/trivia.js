/* News Trivia — answer submission, result reveal, score update.
 * Idempotent via data-trivia-wired sentinel (Turbo 8 safe).
 */
(function () {
  'use strict';

  function init() {
    const container = document.getElementById('trivia-questions');
    if (!container || container.dataset.triviaWired) return;
    container.dataset.triviaWired = '1';

    container.querySelectorAll('.trivia-card:not(.trivia-card-answered)').forEach(wireCard);
  }

  function wireCard(card) {
    card.querySelectorAll('.trivia-choice').forEach(btn => {
      btn.addEventListener('click', () => submitAnswer(card, btn.dataset.letter));
    });
  }

  function submitAnswer(card, letter) {
    const questionId = card.dataset.questionId;
    const correct    = card.dataset.correct;

    // Disable all buttons immediately to prevent double-submit.
    card.querySelectorAll('.trivia-choice').forEach(b => {
      b.disabled = true;
    });

    fetch(`/games/trivia/${questionId}/answer`, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify({ answer: letter })
    })
      .then(r => r.json())
      .then(data => revealResult(card, letter, data))
      .catch(() => {
        // On network error, re-enable so the user can retry.
        card.querySelectorAll('.trivia-choice').forEach(b => { b.disabled = false; });
      });
  }

  function revealResult(card, chosen, data) {
    const correctLetter = data.correct_letter || card.dataset.correct;

    card.classList.add('trivia-card-answered');

    // Style each button.
    card.querySelectorAll('.trivia-choice').forEach(btn => {
      const letter = btn.dataset.letter;
      const mark   = btn.querySelector('.trivia-choice-mark');

      if (letter === correctLetter) {
        btn.classList.add('trivia-choice-correct');
        if (mark) { mark.textContent = '✓'; mark.removeAttribute('aria-hidden'); }
        else {
          const m = document.createElement('span');
          m.className = 'trivia-choice-mark';
          m.textContent = '✓';
          btn.appendChild(m);
        }
      } else if (letter === chosen && !data.correct) {
        btn.classList.add('trivia-choice-wrong');
        if (mark) { mark.textContent = '✗'; mark.removeAttribute('aria-hidden'); }
        else {
          const m = document.createElement('span');
          m.className = 'trivia-choice-mark';
          m.textContent = '✗';
          btn.appendChild(m);
        }
      }
    });

    // Show explanation.
    const expEl = card.querySelector('.trivia-explanation');
    if (expEl && data.explanation) {
      expEl.classList.remove('trivia-explanation-hidden');
      expEl.removeAttribute('aria-hidden');
      const verdict = data.correct ? '✓ Correct!' : '✗ Not quite.';
      expEl.innerHTML =
        `<strong>${verdict}</strong> ${escHtml(data.explanation)}`;
    }

    // Update score badge.
    updateScore();

    // Check for completion.
    const total    = document.querySelectorAll('.trivia-card').length;
    const answered = document.querySelectorAll('.trivia-card-answered').length;
    if (answered >= total) showComplete();
  }

  function updateScore() {
    const scoreEl = document.getElementById('trivia-score-correct');
    if (!scoreEl) return;
    const correct = document.querySelectorAll('.trivia-choice-correct').length;
    scoreEl.textContent = correct;
  }

  function showComplete() {
    let el = document.getElementById('trivia-complete');
    if (el) { el.style.display = ''; return; }

    const correct = document.querySelectorAll('.trivia-choice-correct').length;
    const total   = document.querySelectorAll('.trivia-card').length;

    el = document.createElement('div');
    el.className = 'trivia-complete';
    el.id = 'trivia-complete';
    el.innerHTML =
      `<p class="trivia-complete-score">You scored <strong>${correct} / ${total}</strong></p>` +
      `<a href="/games/sudoku" class="btn btn-secondary">Try today's Sudoku →</a>`;

    const container = document.getElementById('trivia-questions');
    if (container) container.appendChild(el);
  }

  function escHtml(str) {
    return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
              .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  document.addEventListener('DOMContentLoaded', init);
  document.addEventListener('turbo:load', init);
})();
