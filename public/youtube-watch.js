/* YouTube watch tracker. Hooks into the embedded player on
 * /article/:uid (added in PR #71) via YouTube's IFrame API and:
 *
 *   1. Saves + resumes the watch position to localStorage so
 *      reopening the article picks up where you left off.
 *   2. Posts a passive_feedback signal (+1 on ≥80% watched or
 *      `ended`, -1 on close with <10% watched + ≥30s playback)
 *      to /api/podcasts/:uid/feedback — the same endpoint
 *      podcasts use. The route writes to read_state.passive_feedback,
 *      which feeds Recommendation::ForYou's positive/negative
 *      corpora. Result: watching nature/sports videos teaches the
 *      ranker like listening to podcasts already does.
 *
 * The IFrame API is loaded once per page, then attaches to every
 * iframe with class .article-youtube-iframe. Iframe must have
 * src=...?enablejsapi=1 (see views/article.erb) for the API to talk
 * to it, and a data-uid attribute for the localStorage key + POST URL.
 */
(function () {
  'use strict';

  var iframes = document.querySelectorAll('iframe.article-youtube-iframe[data-uid]');
  if (!iframes.length) return;

  var POSITIVE_THRESHOLD = 0.8;  // ≥80% watched = positive signal
  var NEGATIVE_THRESHOLD = 0.1;  // <10% + ≥30s = negative signal
  var NEGATIVE_MIN_TIME  = 30;
  var RESUME_TAIL_S      = 30;   // don't resume if within 30s of end
  var POLL_MS            = 1000;
  var POSITION_KEY       = 'tfr_yt_pos_';
  var WATCHED_MAX_KEY    = 'tfr_yt_max_';
  var PASSIVE_SENT_KEY   = 'tfr_yt_passive_sent_';

  function safeGet(key)        { try { return window.localStorage.getItem(key); } catch (_) { return null; } }
  function safeSet(key, value) { try { window.localStorage.setItem(key, value);  } catch (_) {} }
  function safeRemove(key)     { try { window.localStorage.removeItem(key);     } catch (_) {} }

  function readPos(uid)        { return parseFloat(safeGet(POSITION_KEY + uid))    || 0; }
  function writePos(uid, sec)  { if (isFinite(sec) && sec > 0) safeSet(POSITION_KEY + uid, String(sec)); }
  function clearPos(uid)       { safeRemove(POSITION_KEY + uid); }
  function readMax(uid)        { return parseFloat(safeGet(WATCHED_MAX_KEY + uid)) || 0; }
  function writeMax(uid, sec)  { if (isFinite(sec) && sec > readMax(uid)) safeSet(WATCHED_MAX_KEY + uid, String(sec)); }
  function passiveSent(uid)    { return safeGet(PASSIVE_SENT_KEY + uid); }
  function markPassive(uid, k) { safeSet(PASSIVE_SENT_KEY + uid, k); }

  // Single passive-feedback POST. Once-per-load idempotence (positive
  // on `ended` shouldn't double-fire on pagehide).
  function postPassive(uid, signal, watchedPct, useBeacon) {
    var key = signal === 1 ? 'positive' : 'negative';
    if (passiveSent(uid) === key) return;
    markPassive(uid, key);

    var url = '/api/podcasts/' + encodeURIComponent(uid) + '/feedback';
    var payload = JSON.stringify({ signal: signal, listened_pct: watchedPct });
    try {
      if (useBeacon && navigator.sendBeacon) {
        navigator.sendBeacon(url, new Blob([payload], { type: 'application/json' }));
      } else {
        fetch(url, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: payload,
          keepalive: true
        }).catch(function () { /* best-effort */ });
      }
    } catch (_) { /* best-effort */ }
  }

  // Resolve the passive signal for a single tracker. Mirrors the
  // global-player.js logic so podcasts + videos converge on the same
  // corpus shape.
  function resolveSignal(tracker, opts) {
    var dur = tracker.duration;
    if (!isFinite(dur) || dur <= 0) return null;
    var maxReached = Math.max(tracker.lastTime, readMax(tracker.uid));
    var pct = maxReached / dur;
    if (pct >= POSITIVE_THRESHOLD || (opts && opts.completed)) return { signal: 1, pct: pct };
    if (opts && opts.requireMinTime && pct < NEGATIVE_THRESHOLD && maxReached >= NEGATIVE_MIN_TIME) {
      return { signal: -1, pct: pct };
    }
    return null;
  }

  // Trackers indexed by uid so the pagehide handler can flush all
  // of them. Most pages only render one iframe but it's free to
  // support multiple.
  var trackers = {};

  function makeTracker(iframe) {
    var tracker = {
      iframe:   iframe,
      uid:      iframe.dataset.uid,
      player:   null,
      duration: 0,
      lastTime: 0,
      polling:  false,
      pollId:   null
    };

    tracker.attach = function () {
      tracker.player = new window.YT.Player(iframe, {
        events: {
          onReady:       tracker.onReady,
          onStateChange: tracker.onStateChange
        }
      });
    };

    tracker.onReady = function () {
      tracker.duration = tracker.player.getDuration() || 0;
      var resumeFrom = readPos(tracker.uid);
      if (resumeFrom > 0 && tracker.duration > 0 &&
          resumeFrom < tracker.duration - RESUME_TAIL_S) {
        // seekTo with allowSeekAhead=true buffers the new position.
        // No autoplay — user still has to click to start.
        tracker.player.seekTo(resumeFrom, true);
      }
    };

    tracker.onStateChange = function (event) {
      // YT.PlayerState: -1 unstarted, 0 ended, 1 playing, 2 paused,
      // 3 buffering, 5 cued.
      switch (event.data) {
        case 1:
          tracker.startPolling();
          break;
        case 2:
        case 3:
          tracker.stopPolling();
          tracker.snapshot();
          break;
        case 0:
          tracker.stopPolling();
          tracker.snapshot();
          var resolved = resolveSignal(tracker, { completed: true });
          if (resolved) postPassive(tracker.uid, resolved.signal, resolved.pct, false);
          clearPos(tracker.uid);
          break;
      }
    };

    tracker.startPolling = function () {
      if (tracker.polling) return;
      tracker.polling = true;
      tracker.pollId = setInterval(tracker.snapshot, POLL_MS);
    };

    tracker.stopPolling = function () {
      tracker.polling = false;
      if (tracker.pollId) { clearInterval(tracker.pollId); tracker.pollId = null; }
    };

    tracker.snapshot = function () {
      try {
        var t = tracker.player.getCurrentTime();
        if (!isFinite(t)) return;
        tracker.lastTime = t;
        writePos(tracker.uid, t);
        writeMax(tracker.uid, t);
      } catch (_) { /* IFrame may not be ready, skip */ }
    };

    return tracker;
  }

  // YouTube calls this global when the IFrame API has loaded. The
  // script tag at the bottom of this file triggers the load; if the
  // user already had the API loaded by some other surface, the
  // existing onYouTubeIframeAPIReady callback runs first, so we
  // chain rather than overwrite.
  var prevReady = window.onYouTubeIframeAPIReady;
  window.onYouTubeIframeAPIReady = function () {
    if (typeof prevReady === 'function') { try { prevReady(); } catch (_) {} }
    iframes.forEach(function (iframe) {
      var uid = iframe.dataset.uid;
      if (!uid) return;
      var t = makeTracker(iframe);
      trackers[uid] = t;
      t.attach();
    });
  };

  // Last-ditch flush + passive resolution on tab close.
  window.addEventListener('pagehide', function () {
    Object.keys(trackers).forEach(function (uid) {
      var t = trackers[uid];
      t.snapshot();
      var resolved = resolveSignal(t, { requireMinTime: true });
      if (resolved) postPassive(uid, resolved.signal, resolved.pct, true);
    });
  });

  // STUFF — clickable timestamps in the description. The format
  // helper renders each timestamp as <button class="yt-timestamp"
  // data-seconds="N">; clicking should seek the embedded player and
  // start playback. Delegated on document so it survives if the
  // description block is rendered async someday.
  document.addEventListener('click', function (e) {
    var btn = e.target.closest('.yt-timestamp[data-seconds]');
    if (!btn) return;
    e.preventDefault();
    var sec = parseFloat(btn.dataset.seconds);
    if (!isFinite(sec) || sec < 0) return;
    var uids = Object.keys(trackers);
    if (uids.length === 0) return;
    // Article pages render at most one YouTube iframe, but support
    // multiple defensively by seeking the first one.
    var t = trackers[uids[0]];
    if (!t || !t.player) return;
    try {
      t.player.seekTo(sec, true);
      t.player.playVideo();
      // Smooth-scroll the iframe back into view so the user can see
      // the result of their click (descriptions can be long).
      var ifr = t.iframe;
      if (ifr && typeof ifr.scrollIntoView === 'function') {
        ifr.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
    } catch (_) { /* player may not be ready yet */ }
  });

  // Load the IFrame API once. If another surface already loaded it
  // we don't double-inject; YT's API is idempotent on load anyway.
  if (!window.YT || !window.YT.Player) {
    if (!document.querySelector('script[src*="youtube.com/iframe_api"]')) {
      var s = document.createElement('script');
      s.src = 'https://www.youtube.com/iframe_api';
      s.async = true;
      document.head.appendChild(s);
    }
  } else {
    // Already loaded — fire the ready callback synchronously.
    window.onYouTubeIframeAPIReady();
  }
})();
