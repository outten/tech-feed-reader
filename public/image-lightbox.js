// STUFF #65 — click-to-zoom lightbox for article images.
//
// Wires up two surfaces on /article/:uid:
//   - .article-hero          (the top-of-page image)
//   - .reading-view .article-body img   (any image in the body)
//
// Click → opens a fullscreen overlay with the full-size image.
// Click outside / hit Escape / click the × button → closes.
//
// Turbo 8 fires DOMContentLoaded AND turbo:load on full page loads, so
// both the overlay-init and the per-image wiring are idempotent: the
// overlay is a singleton on window; each <img> carries a
// data-lightbox-bound sentinel after first wire. See the
// feedback_turbo_double_fire memory for why this pattern matters.

(function () {
  function ensureOverlay() {
    let ov = document.getElementById('img-lightbox-overlay');
    if (ov) return ov;

    ov = document.createElement('div');
    ov.id = 'img-lightbox-overlay';
    ov.setAttribute('role', 'dialog');
    ov.setAttribute('aria-modal', 'true');
    ov.setAttribute('aria-label', 'Image viewer');

    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'lightbox-close';
    btn.setAttribute('aria-label', 'Close');
    btn.textContent = '×'; // ×

    const img = document.createElement('img');
    img.alt = '';

    ov.appendChild(btn);
    ov.appendChild(img);
    document.body.appendChild(ov);

    function close() {
      ov.classList.remove('open');
      img.removeAttribute('src');
    }
    ov.addEventListener('click', (e) => {
      // Close when clicking the overlay background OR the close button —
      // but NOT when clicking the image itself.
      if (e.target === ov || e.target === btn) close();
    });
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && ov.classList.contains('open')) close();
    });
    return ov;
  }

  function open(src, alt) {
    const ov = ensureOverlay();
    const img = ov.querySelector('img');
    img.src = src;
    img.alt = alt || '';
    ov.classList.add('open');
  }

  function wireImages() {
    const sel = '.article-hero, .reading-view .article-body img';
    document.querySelectorAll(sel).forEach((img) => {
      if (img.dataset.lightboxBound === '1') return;
      img.dataset.lightboxBound = '1';
      img.addEventListener('click', (e) => {
        // Only the natural full-size URL — skip if the img has no src yet.
        if (!img.src) return;
        e.preventDefault();
        open(img.currentSrc || img.src, img.alt);
      });
    });
  }

  document.addEventListener('DOMContentLoaded', wireImages);
  document.addEventListener('turbo:load', wireImages);
})();
