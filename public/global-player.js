/* Global persistent audio player.
 *
 * The <audio> element + mini-player UI live in the layout under
 * #global-player[data-turbo-permanent], so they survive Turbo
 * navigations — audio keeps playing while the user clicks around.
 *
 * One Player instance per tab, exposed as window.Player. Article
 * pages render a "Play episode" button instead of their own <audio>
 * and call Player.load(...) to start playback in the global player.
 *
 * State persistence:
 *   tfr.podcast.now_playing       — full snapshot for hard reloads
 *                                   (Turbo not in play, e.g. opened
 *                                   in a new tab). Lets the player
 *                                   restore + paused-resume.
 *   tfr.podcast.position.<uid>    — per-episode resume position
 *                                   (existing convention, used when
 *                                   you re-open an episode you
 *                                   previously listened to).
 */
(function () {
  'use strict';

  // ---- Player singleton -------------------------------------------------
  // Guarded init: the script body re-executes on every Turbo body swap,
  // but the #global-player div is data-turbo-permanent so the DOM + the
  // event listeners we attach below MUST stay bound to the same nodes
  // across navigations. The guard prevents double-binding.
  if (!window.__playerInited) {
    window.__playerInited = true;
    initPlayer();
    // ONE persistent listener for state changes — repaints the
    // current page's "Play episode" button if any. Adding this in
    // hookArticlePage instead would leak listeners on every nav.
    window.addEventListener('player:change', paintArticlePageButton);
  }

  // The article-page hookup runs on every script execution — the
  // article body is swapped on each nav, so the button needs to be
  // re-bound. No-op when the current page has no .play-episode element.
  hookArticlePage();

  // ---- implementation --------------------------------------------------
  function initPlayer() {
    var root        = document.getElementById('global-player');
    if (!root) return;
    var audio       = document.getElementById('global-audio');
    var titleEl     = document.getElementById('mini-player-title');
    var playBtn     = document.getElementById('mini-player-play');
    var skipBackBtn = document.getElementById('mini-player-skip-back');
    var skipFwdBtn  = document.getElementById('mini-player-skip-fwd');
    var currentEl   = document.getElementById('mini-player-current');
    var durationEl  = document.getElementById('mini-player-duration');
    var scrubber    = document.getElementById('mini-player-scrubber');
    var rateSelect  = document.getElementById('mini-player-rate');
    var closeBtn    = document.getElementById('mini-player-close');

    var SKIP_BACK_S      = 15;
    var SKIP_FWD_S       = 30;
    var SAVE_THROTTLE_MS = 5_000;
    var RESUME_TAIL_S    = 30;
    var STORAGE_NOW      = 'tfr.podcast.now_playing';
    var STORAGE_POS      = 'tfr.podcast.position.';

    // Phase 4 — passive listened-percent signal. We track the max
    // currentTime reached (not just current) so a user who scrubs
    // back doesn't downgrade their own signal. Two terminal signals:
    //   ended     ⇒ +1 (listened to completion)
    //   pagehide  ⇒ +1 if pct ≥ 0.80
    //              -1 if pct < 0.10 AND >30s of actual playback
    //   else       ⇒ no post (ambiguous; listening but not done)
    // The 30s lower bound on the negative path keeps a 3-second
    // "what's this?" tap from getting demoted. Sent at most once per
    // (episode, signal) — guarded by a session set.
    var STORAGE_LISTENED   = 'tfr.podcast.listened.';
    var POSITIVE_THRESHOLD = 0.80;
    var NEGATIVE_THRESHOLD = 0.10;
    var NEGATIVE_MIN_TIME  = 30;        // seconds of actual playback before a low-% counts as "skip"
    var passiveSent = {};               // { uid: 'positive' | 'negative' } — once-per-load guard

    var state = null;          // { uid, url, mime, title, articleUrl, duration }
    var scrubbing = false;
    var lastSavedAt = 0;

    // ---- storage helpers ----
    function readNow() {
      try {
        var raw = localStorage.getItem(STORAGE_NOW);
        return raw ? JSON.parse(raw) : null;
      } catch (_) { return null; }
    }
    function writeNow(extra) {
      if (!state) return;
      var now = Date.now();
      var snap = {
        uid:         state.uid,
        url:         state.url,
        mime:        state.mime || '',
        title:       state.title || '',
        articleUrl:  state.articleUrl || '',
        duration:    state.duration || 0,
        currentTime: audio.currentTime || 0,
        paused:      audio.paused,
        rate:        audio.playbackRate || 1,
        savedAt:     now
      };
      if (extra) Object.keys(extra).forEach(function (k) { snap[k] = extra[k]; });
      try { localStorage.setItem(STORAGE_NOW, JSON.stringify(snap)); } catch (_) {}
      lastSavedAt = now;
    }
    function clearNow() {
      try { localStorage.removeItem(STORAGE_NOW); } catch (_) {}
    }
    function readPosition(uid) {
      try {
        var raw = localStorage.getItem(STORAGE_POS + uid);
        var v = raw ? parseFloat(raw) : NaN;
        return isFinite(v) && v >= 0 ? v : NaN;
      } catch (_) { return NaN; }
    }
    function writePosition(uid, seconds) {
      try { localStorage.setItem(STORAGE_POS + uid, String(seconds)); } catch (_) {}
    }
    function clearPosition(uid) {
      try { localStorage.removeItem(STORAGE_POS + uid); } catch (_) {}
    }
    // Phase 4 — track the high-watermark currentTime reached for an
    // episode. Stored as seconds; writePct() also stores the duration
    // at the time so listened_pct survives a hard reload even if
    // audio.duration hasn't loaded yet on restoration.
    function readListenedSeconds(uid) {
      try {
        var raw = localStorage.getItem(STORAGE_LISTENED + uid);
        var v = raw ? parseFloat(raw) : NaN;
        return isFinite(v) && v >= 0 ? v : 0;
      } catch (_) { return 0; }
    }
    function writeListenedSeconds(uid, seconds) {
      try { localStorage.setItem(STORAGE_LISTENED + uid, String(seconds)); } catch (_) {}
    }
    function postPassive(uid, signal, listenedPct, useBeacon) {
      // Once-per-load idempotence: a positive on `ended` shouldn't
      // double-fire on the subsequent pagehide.
      var key = signal === 1 ? 'positive' : 'negative';
      if (passiveSent[uid] === key) return;
      passiveSent[uid] = key;

      var url = '/api/podcasts/' + encodeURIComponent(uid) + '/feedback';
      var payload = JSON.stringify({ signal: signal, listened_pct: listenedPct });
      try {
        if (useBeacon && navigator.sendBeacon) {
          // sendBeacon must use a Blob with a JSON content-type for
          // Sinatra's request.body parser to see it correctly.
          navigator.sendBeacon(url, new Blob([payload], { type: 'application/json' }));
        } else {
          fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: payload,
            keepalive: true
          }).catch(function () { /* best-effort, drop errors */ });
        }
      } catch (_) { /* best-effort */ }
    }
    // Resolves the current passive signal for the active episode, or
    // null if it's still ambiguous. Caller passes whether to apply the
    // negative-path 30s minimum (false on `ended`, true on `pagehide`).
    function resolvePassiveSignal(opts) {
      if (!state || !state.uid) return null;
      var dur = isFinite(audio.duration) && audio.duration > 0 ? audio.duration : (state.duration || 0);
      if (dur <= 0) return null;
      var maxReached = Math.max(audio.currentTime || 0, readListenedSeconds(state.uid));
      var pct = maxReached / dur;
      if (pct >= POSITIVE_THRESHOLD || (opts && opts.completed)) return { signal: 1, pct: pct };
      if (opts && opts.requireMinTime && pct < NEGATIVE_THRESHOLD && maxReached >= NEGATIVE_MIN_TIME) {
        return { signal: -1, pct: pct };
      }
      return null;
    }

    // ---- formatting ----
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

    // ---- paint ----
    function paintTime() {
      if (state && state.live) {
        currentEl.textContent = '● LIVE';
        durationEl.textContent = '';
        return;
      }
      currentEl.textContent = fmt(audio.currentTime);
      var d = isFinite(audio.duration) ? audio.duration : (state && state.duration);
      durationEl.textContent = fmt(d);
      if (!scrubbing && isFinite(audio.duration) && audio.duration > 0) {
        scrubber.value = (audio.currentTime / audio.duration) * 100;
      }
    }
    function paintPlay() {
      var paused = audio.paused;
      playBtn.textContent = paused ? '▶' : '❚❚';
      playBtn.setAttribute('aria-label', paused ? 'Play' : 'Pause');
      // Tell article-page hookups to refresh their "Play"/"Now playing"
      // button label.
      window.dispatchEvent(new CustomEvent('player:change', { detail: snapshot() }));
    }
    function paintTitle() {
      if (!state) {
        titleEl.textContent = '—';
        titleEl.removeAttribute('href');
        return;
      }
      titleEl.textContent = state.title || 'Episode';
      if (state.articleUrl) titleEl.setAttribute('href', state.articleUrl);
      else titleEl.removeAttribute('href');
    }

    // ---- audio events ----
    audio.addEventListener('loadedmetadata', paintTime);
    audio.addEventListener('timeupdate', function () {
      paintTime();
      // Throttled save so we don't hammer localStorage every 250ms.
      var now = Date.now();
      if (state && !scrubbing && now - lastSavedAt > SAVE_THROTTLE_MS) {
        writeNow();
        if (audio.currentTime > RESUME_TAIL_S) writePosition(state.uid, audio.currentTime);
        // Phase 4: keep the listened-pct high-watermark in sync. We
        // only ever bump it upward, so scrubbing back doesn't undo
        // progress — same intent as positionStore.
        if (state.uid && audio.currentTime > readListenedSeconds(state.uid)) {
          writeListenedSeconds(state.uid, audio.currentTime);
        }
      }
    });
    audio.addEventListener('play',  function () { paintPlay(); writeNow(); });
    audio.addEventListener('pause', function () { paintPlay(); writeNow(); });
    audio.addEventListener('ended', function () {
      paintPlay();
      // Phase 4: full-listen is the cleanest positive signal we'll
      // ever get. Resolve before clearing position, so duration is
      // still valid.
      if (state && state.uid) {
        var resolved = resolvePassiveSignal({ completed: true });
        if (resolved) postPassive(state.uid, resolved.signal, resolved.pct, false);
      }
      if (state) clearPosition(state.uid);
      clearNow();
    });
    audio.addEventListener('seeked', function () {
      writeNow();
      if (state) writePosition(state.uid, audio.currentTime);
    });

    // Capture position on tab close — guards against losing the last
    // 5s of progress when SAVE_THROTTLE_MS hasn't elapsed.
    window.addEventListener('pagehide', function () {
      if (state) {
        writeNow();
        if (audio.currentTime > RESUME_TAIL_S) writePosition(state.uid, audio.currentTime);
        if (state.uid && audio.currentTime > readListenedSeconds(state.uid)) {
          writeListenedSeconds(state.uid, audio.currentTime);
        }
        // Phase 4: post the resolved passive signal. requireMinTime
        // gates the negative path (don't fire 👎 on a 3s sample).
        var resolved = resolvePassiveSignal({ requireMinTime: true });
        if (resolved) postPassive(state.uid, resolved.signal, resolved.pct, true);
      }
    });

    // ---- UI events ----
    playBtn.addEventListener('click', function () {
      // STUFF.md #19 — rewind to 0 if the track previously played
      // through, otherwise play() does nothing and the button feels
      // broken. Pause path is unchanged.
      if (audio.paused) { rewindIfAtEnd(); audio.play(); }
      else { audio.pause(); }
    });
    skipBackBtn.addEventListener('click', function () {
      audio.currentTime = Math.max(0, audio.currentTime - SKIP_BACK_S);
    });
    skipFwdBtn.addEventListener('click', function () {
      var max = isFinite(audio.duration) ? audio.duration : Infinity;
      audio.currentTime = Math.min(max, audio.currentTime + SKIP_FWD_S);
    });
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
      if (isFinite(r) && r > 0) {
        audio.playbackRate = r;
        writeNow();
      }
    });
    closeBtn.addEventListener('click', function () {
      pause();
      hide();
      state = null;
      audio.removeAttribute('src');
      audio.load();
      clearNow();
      paintTitle();
      window.dispatchEvent(new CustomEvent('player:change', { detail: snapshot() }));
    });

    // ---- public API on window.Player ----
    function show() { root.removeAttribute('hidden'); document.body.classList.add('has-mini-player'); }
    function hide() { root.setAttribute('hidden', ''); document.body.classList.remove('has-mini-player'); }
    function pause() { if (!audio.paused) audio.pause(); }

    // STUFF.md #19 — when an audio element has played through (ended)
    // its currentTime sits at duration. A subsequent play() call has
    // nothing to play and fires `ended` again immediately — the user
    // sees nothing happen. Rewind to 0 before play() in that case so
    // "Play episode" on a finished show restarts it. Returns true
    // when a rewind was needed (caller can short-circuit a resume
    // seek if it just reset us). Tolerance of 0.5s covers float drift.
    function rewindIfAtEnd() {
      if (!isFinite(audio.duration) || audio.duration <= 0) return false;
      if (audio.ended || audio.currentTime >= audio.duration - 0.5) {
        audio.currentTime = 0;
        return true;
      }
      return false;
    }

    function loadEpisode(ep, opts) {
      opts = opts || {};
      var sameEpisode = state && state.uid === ep.uid;
      var isLive      = !!ep.live;
      state = {
        uid:        ep.uid,
        url:        ep.url,
        mime:       ep.mime || '',
        title:      ep.title || '',
        articleUrl: ep.articleUrl || '',
        duration:   parseFloat(ep.duration) || 0,
        live:       isLive
      };

      // Live streams: hide scrubber + skip buttons, show LIVE badge.
      root.classList.toggle('is-live-stream', isLive);

      paintTitle();
      show();

      if (!sameEpisode) {
        if (ep.mime) audio.setAttribute('type', ep.mime); else audio.removeAttribute('type');
        audio.src = ep.url;
        audio.load();

        // Skip resume logic for live streams — you always join mid-stream.
        if (!isLive) {
          var resumeFrom = (opts.resumeFrom != null) ? opts.resumeFrom : readPosition(ep.uid);
          if (isFinite(resumeFrom) && resumeFrom > 0) {
            var seekOnce = function () {
              audio.removeEventListener('loadedmetadata', seekOnce);
              var max = isFinite(audio.duration) ? audio.duration : Infinity;
              if (resumeFrom < max - RESUME_TAIL_S) audio.currentTime = resumeFrom;
            };
            audio.addEventListener('loadedmetadata', seekOnce);
          }
        }
      } else {
        if (!isLive) rewindIfAtEnd();
      }

      if (opts.autoplay !== false) {
        var p = audio.play();
        if (p && p.catch) p.catch(function () { /* autoplay blocked — leave paused */ });
      }
    }

    function snapshot() {
      if (!state) return { active: false };
      return {
        active:      true,
        uid:         state.uid,
        title:       state.title,
        articleUrl:  state.articleUrl,
        currentTime: audio.currentTime,
        duration:    audio.duration || state.duration,
        paused:      audio.paused
      };
    }

    window.Player = {
      load:    loadEpisode,
      pause:   pause,
      resume:  function () { rewindIfAtEnd(); var p = audio.play(); if (p && p.catch) p.catch(function () {}); },
      toggle:  function () {
        if (audio.paused) { rewindIfAtEnd(); audio.play(); }
        else { audio.pause(); }
      },
      close:   function () { closeBtn.click(); },
      state:   snapshot,
      isActive:   function () { return !!state; },
      isPlaying:  function () { return state && !audio.paused; }
    };

    // ---- restore on first load ----
    var restored = readNow();
    if (restored && restored.url) {
      loadEpisode(
        {
          uid:        restored.uid,
          url:        restored.url,
          mime:       restored.mime,
          title:      restored.title,
          articleUrl: restored.articleUrl,
          duration:   restored.duration
        },
        { resumeFrom: restored.currentTime, autoplay: !restored.paused }
      );
      if (restored.rate) audio.playbackRate = restored.rate;
      if (restored.rate) rateSelect.value = String(restored.rate);
    }
  }

  // ---- article-page hookup --------------------------------------------
  // Article pages render <button class="play-episode" data-uid=... etc>
  // instead of their own <audio>. Wire the click handler each time the
  // page loads (the global player:change listener registered in
  // initPlayer takes care of the label).
  function hookArticlePage() {
    var btn = document.querySelector('.play-episode');
    if (!btn || !window.Player) return;
    if (btn.dataset.bound === '1') return;
    btn.dataset.bound = '1';

    btn.addEventListener('click', function (e) {
      e.preventDefault();
      var st = window.Player.state();
      if (st.active && st.uid === btn.dataset.uid) {
        window.Player.toggle();
      } else {
        window.Player.load({
          uid:        btn.dataset.uid,
          url:        btn.dataset.audioUrl,
          mime:       btn.dataset.audioMime,
          title:      btn.dataset.title,
          articleUrl: btn.dataset.articleUrl,
          duration:   parseFloat(btn.dataset.duration) || 0
        });
      }
    });

    paintArticlePageButton();
  }

  // Repaints the current page's "Play episode" button to reflect
  // Player state. Called on every player:change event (one global
  // listener registered in initPlayer above) plus once after each
  // hookArticlePage so the button is correct on initial load.
  function paintArticlePageButton() {
    var btn = document.querySelector('.play-episode');
    if (!btn || !window.Player) return;
    var st = window.Player.state();
    if (st.active && st.uid === btn.dataset.uid) {
      btn.textContent = st.paused ? '▶ Resume' : '❚❚ Pause';
      btn.classList.add('play-episode-active');
    } else {
      btn.textContent = '▶ Play episode';
      btn.classList.remove('play-episode-active');
    }
  }
})();
