/* Continue listening / watching tile on /.
 *
 * Position state for in-progress media lives client-side:
 *   • Podcasts → localStorage["tfr.podcast.position." + uid] (global-player.js)
 *   • YouTube  → localStorage["tfr_yt_pos_" + uid]            (youtube-watch.js)
 *
 * The server can't see those, so this script scans both prefixes,
 * batches the uids into GET /api/articles/lookup, and renders one
 * tile per still-tracked item into the #continue-progress slot on
 * the home view (returning-user branch). Hidden when nothing's in
 * progress.
 *
 * Renders a single mixed row (podcasts + videos together) sorted by
 * insertion order — i.e. whatever localStorage walked through first.
 * That's close enough to "most recently touched" for v1 since the
 * player writes positions only while you're actively scrubbing. */
(function () {
  'use strict';

  var slot = document.getElementById('continue-progress');
  if (!slot) return;

  var PODCAST_PREFIX = 'tfr.podcast.position.';
  var YT_PREFIX      = 'tfr_yt_pos_';
  var MIN_SECONDS    = 5;     // skip near-start positions (noise)
  var MAX_ITEMS      = 6;

  function collect() {
    var items = [];
    try {
      for (var i = 0; i < window.localStorage.length; i++) {
        var key = window.localStorage.key(i);
        if (!key) continue;
        var prefix, kind;
        if (key.indexOf(PODCAST_PREFIX) === 0) { prefix = PODCAST_PREFIX; kind = 'podcast'; }
        else if (key.indexOf(YT_PREFIX) === 0)  { prefix = YT_PREFIX;      kind = 'video';   }
        else continue;
        var uid = key.slice(prefix.length);
        var seconds = parseFloat(window.localStorage.getItem(key));
        if (!isFinite(seconds) || seconds < MIN_SECONDS) continue;
        items.push({ uid: uid, kind: kind, seconds: seconds });
      }
    } catch (_) { /* localStorage may be disabled — fail silent */ }
    return items.slice(0, MAX_ITEMS);
  }

  function fmtTime(seconds) {
    if (!isFinite(seconds) || seconds <= 0) return '0:00';
    var s = Math.floor(seconds);
    var m = Math.floor(s / 60);
    var ss = String(s % 60).padStart(2, '0');
    if (m < 60) return m + ':' + ss;
    var h = Math.floor(m / 60);
    var mm = String(m % 60).padStart(2, '0');
    return h + ':' + mm + ':' + ss;
  }

  function render(payloadByUid, items) {
    // Sort: videos first (more visual), then by uid alphabetic for
    // deterministic order across reloads.
    items.sort(function (a, b) {
      if (a.kind !== b.kind) return a.kind === 'video' ? -1 : 1;
      return a.uid < b.uid ? -1 : 1;
    });

    var ul = document.createElement('ul');
    ul.className = 'continue-progress-list';

    items.forEach(function (item) {
      var meta = payloadByUid[item.uid];
      if (!meta) return;
      var li = document.createElement('li');
      li.className = 'continue-progress-item continue-progress-' + item.kind;

      var thumb = document.createElement('a');
      thumb.className = 'continue-progress-thumb';
      thumb.href = '/article/' + encodeURIComponent(item.uid);
      thumb.title = 'Resume ' + (meta.title || '');
      if (item.kind === 'video') {
        var img = document.createElement('img');
        img.alt = '';
        img.loading = 'lazy';
        img.src = 'https://i.ytimg.com/vi/' + extractYtId(meta.url) + '/hqdefault.jpg';
        thumb.appendChild(img);
      } else if (meta.feed_image_url) {
        var img2 = document.createElement('img');
        img2.alt = '';
        img2.loading = 'lazy';
        img2.src = meta.feed_image_url;
        thumb.appendChild(img2);
      }
      var play = document.createElement('span');
      play.className = 'continue-progress-play';
      play.setAttribute('aria-hidden', 'true');
      play.textContent = item.kind === 'video' ? '▶' : '🎧';
      thumb.appendChild(play);
      li.appendChild(thumb);

      var body = document.createElement('div');
      body.className = 'continue-progress-body';

      var title = document.createElement('a');
      title.className = 'continue-progress-title';
      title.href = '/article/' + encodeURIComponent(item.uid);
      title.textContent = meta.title || '(untitled)';
      body.appendChild(title);

      var resume = document.createElement('div');
      resume.className = 'continue-progress-resume';
      var dur = parseFloat(meta.audio_duration_seconds) || 0;
      resume.textContent = 'Resume at ' + fmtTime(item.seconds) +
                           (dur > 0 ? ' / ' + fmtTime(dur) : '');
      body.appendChild(resume);

      if (meta.feed_title) {
        var feed = document.createElement('div');
        feed.className = 'continue-progress-feed muted';
        feed.textContent = meta.feed_title;
        body.appendChild(feed);
      }

      li.appendChild(body);
      ul.appendChild(li);
    });

    if (!ul.children.length) return false;
    slot.innerHTML = '';
    var h = document.createElement('h3');
    h.innerHTML = '▶ Pick up where you left off <span class="muted whats-on-count">(' + ul.children.length + ')</span>';
    slot.appendChild(h);
    slot.appendChild(ul);
    slot.removeAttribute('hidden');
    return true;
  }

  function extractYtId(url) {
    if (!url) return '';
    var m = url.match(/[?&]v=([\w-]{11})/) ||
            url.match(/youtube\.com\/(?:embed|v|shorts)\/([\w-]{11})/) ||
            url.match(/youtu\.be\/([\w-]{11})/);
    return m ? m[1] : '';
  }

  var items = collect();
  if (!items.length) return;
  var url = '/api/articles/lookup?uids=' + items.map(function (i) { return encodeURIComponent(i.uid); }).join(',');
  fetch(url, { credentials: 'same-origin' })
    .then(function (r) { return r.ok ? r.json() : Promise.reject(); })
    .then(function (data) {
      var byUid = {};
      (data.articles || []).forEach(function (a) { byUid[a.uid] = a; });
      render(byUid, items);
    })
    .catch(function () { /* offline / 500 → just don't render */ });
})();
