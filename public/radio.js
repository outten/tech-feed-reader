/* Internet Radio — play button + follow/unfollow toggle.
 * Loaded from layout.erb; bails immediately on non-radio pages.
 */
(function () {
  'use strict';

  function init() {
    if (!document.querySelector('.radio-page')) return;
    if (document.querySelector('.radio-page').dataset.radioWired) return;
    document.querySelector('.radio-page').dataset.radioWired = '1';

    // ── Play buttons ──────────────────────────────────────────────────────
    document.querySelectorAll('.radio-play-btn').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var url   = btn.dataset.streamUrl;
        var name  = btn.dataset.stationName;
        var image = btn.dataset.stationImage;
        var id    = btn.dataset.stationId;

        if (!window.Player) return;
        window.Player.load({
          uid:      'radio-' + id,
          url:      url,
          title:    name,
          imageUrl: image || '',
          live:     true
        });

        // Visual: mark this card as currently playing.
        document.querySelectorAll('.radio-card').forEach(function (c) {
          c.classList.remove('radio-card-playing');
        });
        var card = document.getElementById('radio-card-' + id);
        if (card) card.classList.add('radio-card-playing');
      });
    });

    // ── Follow / unfollow ─────────────────────────────────────────────────
    document.querySelectorAll('.radio-follow-btn, .radio-following-btn').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var id       = btn.dataset.stationId;
        var isFollow = btn.classList.contains('radio-follow-btn');
        var url      = isFollow ? '/radio/follow' : '/radio/unfollow';

        btn.disabled = true;

        var body = new URLSearchParams({ station_id: id });
        fetch(url, {
          method:  'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body:    body.toString()
        })
          .then(function (r) { return r.json(); })
          .then(function (data) {
            if (!data.ok) return;
            if (data.following) {
              btn.textContent = '✓ Following';
              btn.classList.replace('radio-follow-btn', 'radio-following-btn');
            } else {
              btn.textContent = '+ Follow';
              btn.classList.replace('radio-following-btn', 'radio-follow-btn');
            }
            btn.disabled = false;
          })
          .catch(function () { btn.disabled = false; });
      });
    });
  }

  document.addEventListener('DOMContentLoaded', init);
  document.addEventListener('turbo:load', init);
})();
