/* STUFF #54 — AJAX follow/unfollow for sports surfaces.
 *
 * The same .js-sports-follow-form is shipped on /sports/tennis,
 * /sports/player/:slug, /sports/team/:slug, and /sports/manage/:sport/:league.
 * Server returns {ok, slug, kind, followed} when Accept: application/json;
 * we toggle the button state in-place and rewrite the form's action so
 * the next click toggles the other way. No reload, no scroll loss.
 *
 * Modeled on public/article-feedback.js. Guards against double-binding
 * across DOMContentLoaded + turbo:load (see feedback-turbo-double-fire
 * memory: Turbo 8 fires both events on a full page load, so init runs
 * twice without a sentinel).
 */
(function () {
  'use strict';

  function init() {
    if (document.body.dataset.sportsFollowBound === '1') return;
    document.body.dataset.sportsFollowBound = '1';
    // Listen on the form's submit event (more robust than click —
    // fires regardless of how the submit was triggered, and lets
    // preventDefault unambiguously cancel the navigation).
    document.body.addEventListener('submit', onSubmit, true);
  }

  function onSubmit(e) {
    var form = e.target;
    if (!form || !form.matches || !form.matches('form.js-sports-follow-form')) return;
    e.preventDefault();
    var btn = form.querySelector('button[type="submit"]');
    submit(form, btn);
  }

  function submit(form, btn) {
    var slugInput = form.querySelector('input[name="slug"]');
    var body = new URLSearchParams();
    body.set('slug', slugInput ? slugInput.value : '');

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
        // Fall back to a full submit so the user isn't left in a stuck
        // state — the server's 302 path is still valid.
        console.warn('[sports-follow] AJAX failed, falling back to form submit', err);
        form.submit();  // disabled button stays disabled briefly; navigation overrides
      })
      .finally(function () { btn.disabled = false; });
  }

  function applyState(form, btn, data) {
    var followed = !!data.followed;
    var slug     = data.slug || '';
    var kind     = data.kind || (form.action.indexOf('/players/') !== -1 ? 'player' : 'team');

    // Flip the form's action so the next click does the opposite.
    var base = kind === 'player' ? '/sports/players/' : '/sports/teams/';
    form.action = base + (followed ? 'unfollow' : 'follow');

    // Update the button visual: ★ for followed, ☆ for unfollowed.
    // Container classes / labels follow the existing tennis pattern;
    // sports_manage_league.erb uses pill-button text instead so we
    // swap that text too if present.
    btn.classList.toggle('is-followed', followed);
    btn.classList.toggle('is-following', followed);  // alias used by team grid
    btn.setAttribute('aria-label', (followed ? 'Unfollow ' : 'Follow ') + (btn.dataset.fullName || slug));
    btn.setAttribute('title',      (followed ? 'Unfollow ' : 'Follow ') + (btn.dataset.fullName || slug));

    // Tennis: ☆ / ★ glyph button.
    if (btn.textContent.trim() === '☆' || btn.textContent.trim() === '★') {
      btn.textContent = followed ? '★' : '☆';
    }
    // Team grid: text button ("+ Follow" / "✓ Following").
    var followLabel   = btn.dataset.followLabel   || '+ Follow';
    var followingLabel = btn.dataset.followingLabel || '✓ Following';
    if (btn.dataset.followLabel || btn.dataset.followingLabel) {
      btn.textContent = followed ? followingLabel : followLabel;
    }
  }

  init();
  document.addEventListener('turbo:load', init);
})();
