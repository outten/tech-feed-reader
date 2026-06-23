// Fetch intraday sparklines for major indices and draw them on the
// canvas elements.  Runs after page load so the initial render isn't
// blocked by the Yahoo Finance round-trip.
(function () {
  'use strict';

  var canvases = document.querySelectorAll('canvas.stock-spark');
  if (!canvases.length) return;

  fetch('/api/stocks/sparklines')
    .then(function (res) { return res.json(); })
    .then(function (data) {
      canvases.forEach(function (canvas) {
        var sym = canvas.dataset.symbol;
        var closes = data[sym];
        if (!closes || closes.length < 2) {
          canvas.style.display = 'none';
          return;
        }
        drawSparkline(canvas, closes);
      });
    })
    .catch(function () {
      // Silently degrade — sparklines are eye-candy, not critical.
      canvases.forEach(function (c) { c.style.display = 'none'; });
    });

  function drawSparkline(canvas, data) {
    var dpr = window.devicePixelRatio || 1;
    var w = canvas.offsetWidth;
    var h = 40;
    if (!w) return;
    canvas.width = Math.round(w * dpr);
    canvas.height = Math.round(h * dpr);
    var ctx = canvas.getContext('2d');
    ctx.scale(dpr, dpr);

    var min = Math.min.apply(null, data);
    var max = Math.max.apply(null, data);
    var range = max - min || 1;
    var pad = 2;

    var isUp = data[data.length - 1] >= data[0];
    var color = isUp ? '#34c759' : '#ff3b30';

    // Line
    ctx.beginPath();
    for (var i = 0; i < data.length; i++) {
      var x = (i / (data.length - 1)) * w;
      var y = pad + (1 - (data[i] - min) / range) * (h - pad * 2);
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.strokeStyle = color;
    ctx.lineWidth = 1.5;
    ctx.lineJoin = 'round';
    ctx.stroke();

    // Fill under the line
    ctx.lineTo(w, h);
    ctx.lineTo(0, h);
    ctx.closePath();
    var isDark = document.documentElement.getAttribute('data-theme') !== 'light';
    ctx.fillStyle = isUp
      ? (isDark ? 'rgba(52,199,89,0.12)' : 'rgba(52,199,89,0.08)')
      : (isDark ? 'rgba(255,69,58,0.12)' : 'rgba(255,69,58,0.08)');
    ctx.fill();
  }
})();
