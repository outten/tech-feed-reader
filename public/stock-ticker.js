(function () {
  const POLL_MS = 5 * 60 * 1000;
  let pollTimer = null;
  let inited = false;

  function setDuration(track, itemCount) {
    track.style.animationDuration = Math.max(itemCount * 3, 20) + 's';
  }

  function buildTrack(section, items) {
    const track = section.querySelector('.stock-ticker-track');
    if (!track) return;

    let html = '';
    [false, true].forEach(function (hidden) {
      items.forEach(function (q) {
        const attrs = hidden ? ' aria-hidden="true" tabindex="-1"' : '';
        const title = (q.name || q.symbol).replace(/"/g, '&quot;');
        let inner = '<span class="stock-ticker-symbol">' + esc(q.symbol) + '</span>';
        if (q.price != null) {
          const pct = parseFloat(q.change_pct || 0);
          const chg = parseFloat(q.change || 0);
          const dir = chg >= 0 ? 'positive' : 'negative';
          const arrow = chg >= 0 ? '▲' : '▼';
          inner +=
            '<span class="stock-ticker-price">' + formatPrice(q.price) + '</span>' +
            '<span class="stock-ticker-change ' + dir + '">' + arrow + ' ' + formatPct(pct) + '</span>';
        }
        html += '<a href="/stocks/' + encodeURIComponent(q.symbol) +
          '" class="stock-ticker-item"' + attrs +
          ' title="' + title + '">' + inner + '</a>';
      });
    });

    track.innerHTML = html;
    setDuration(track, items.length);
  }

  function formatPrice(val) {
    return parseFloat(val).toFixed(2);
  }

  function formatPct(val) {
    return Math.abs(parseFloat(val)).toFixed(2) + '%';
  }

  function esc(str) {
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  function refresh(section) {
    fetch('/api/ticker', { headers: { Accept: 'application/json' } })
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (items) { buildTrack(section, items); })
      .catch(function () { /* leave existing content unchanged */ });
  }

  function init() {
    const section = document.getElementById('stock-ticker');
    if (!section) return;

    const track = section.querySelector('.stock-ticker-track');
    const existing = track ? track.querySelectorAll('.stock-ticker-item') : [];

    if (!inited) {
      inited = true;
      // Only start the poll timer once; it survives Turbo navigations.
      pollTimer = setInterval(function () {
        const s = document.getElementById('stock-ticker');
        if (s) refresh(s);
      }, POLL_MS);
    }

    if (existing.length > 0) {
      // SSR content present — set duration from item count (half, since track is duplicated)
      setDuration(track, existing.length / 2);
    } else {
      // Cold start — fetch immediately
      refresh(section);
    }
  }

  document.addEventListener('DOMContentLoaded', init);
  document.addEventListener('turbo:load', init);
}());
