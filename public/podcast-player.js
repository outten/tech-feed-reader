/* Custom controls over the <audio> element rendered by views/article.erb.
 *
 * One player per page (the article view has at most one), so we look it
 * up once on load. The <audio> tag carries `preload="metadata"` so the
 * browser fetches just the duration header on page load — actual bytes
 * don't move until the user clicks Play.
 *
 * If `data-duration-seconds` is present (parsed from itunes:duration at
 * import time), we paint the runtime immediately so the user sees how
 * long the episode is before audio metadata loads.
 */
(function () {
  'use strict';

  var root = document.querySelector('.podcast-player');
  if (!root) return;
  var audio = root.querySelector('audio');
  if (!audio) return;

  var playBtn      = root.querySelector('.player-play');
  var skipBackBtn  = root.querySelector('.player-skip-back');
  var skipFwdBtn   = root.querySelector('.player-skip-forward');
  var currentEl    = root.querySelector('.player-current');
  var durationEl   = root.querySelector('.player-duration');
  var scrubber     = root.querySelector('.player-scrubber');
  var rateSelect   = root.querySelector('.player-rate');

  var SKIP_BACK_S    = 15;
  var SKIP_FORWARD_S = 30;
  var scrubbing      = false;

  function fmt(seconds) {
    if (!isFinite(seconds) || seconds < 0) return '—';
    var s = Math.floor(seconds);
    var h = Math.floor(s / 3600);
    var m = Math.floor((s % 3600) / 60);
    var sec = s % 60;
    var mm = (h > 0 && m < 10 ? '0' : '') + m;
    var ss = (sec < 10 ? '0' : '') + sec;
    return h > 0 ? h + ':' + mm + ':' + ss : m + ':' + ss;
  }

  function paintTime() {
    currentEl.textContent = fmt(audio.currentTime);
    var d = isFinite(audio.duration) ? audio.duration : parseFloat(root.dataset.durationSeconds);
    durationEl.textContent = fmt(d);
    if (!scrubbing && isFinite(audio.duration) && audio.duration > 0) {
      scrubber.value = (audio.currentTime / audio.duration) * 100;
    }
  }

  function paintPlayState() {
    var paused = audio.paused;
    playBtn.textContent = paused ? '▶' : '❚❚';
    playBtn.setAttribute('aria-label', paused ? 'Play' : 'Pause');
  }

  // Render the cached duration immediately so the runtime is visible
  // before the browser pulls audio metadata.
  paintTime();

  audio.addEventListener('loadedmetadata', paintTime);
  audio.addEventListener('timeupdate',     paintTime);
  audio.addEventListener('play',           paintPlayState);
  audio.addEventListener('pause',          paintPlayState);
  audio.addEventListener('ended',          paintPlayState);

  playBtn.addEventListener('click', function () {
    if (audio.paused) audio.play(); else audio.pause();
  });

  skipBackBtn.addEventListener('click', function () {
    audio.currentTime = Math.max(0, audio.currentTime - SKIP_BACK_S);
    paintTime();
  });

  skipFwdBtn.addEventListener('click', function () {
    var max = isFinite(audio.duration) ? audio.duration : Infinity;
    audio.currentTime = Math.min(max, audio.currentTime + SKIP_FORWARD_S);
    paintTime();
  });

  // Scrubber semantics: holding it down pauses position updates so the
  // user can drag without the time-update listener fighting them. On
  // release we seek to the chosen percent and resume normal painting.
  scrubber.addEventListener('input', function () {
    scrubbing = true;
    if (isFinite(audio.duration) && audio.duration > 0) {
      currentEl.textContent = fmt((scrubber.value / 100) * audio.duration);
    }
  });
  scrubber.addEventListener('change', function () {
    if (isFinite(audio.duration) && audio.duration > 0) {
      audio.currentTime = (scrubber.value / 100) * audio.duration;
    }
    scrubbing = false;
  });

  rateSelect.addEventListener('change', function () {
    var r = parseFloat(rateSelect.value);
    if (isFinite(r) && r > 0) audio.playbackRate = r;
  });

  // Spacebar toggles play/pause when the player is the closest focus
  // root and the user isn't typing into a form field.
  document.addEventListener('keydown', function (e) {
    if (e.code !== 'Space') return;
    var t = e.target;
    if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable)) return;
    e.preventDefault();
    if (audio.paused) audio.play(); else audio.pause();
  });
})();
