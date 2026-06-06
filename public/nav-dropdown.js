// Nav dropdown click-to-toggle.  Clicking the trigger pins the menu
// open (adds .open); clicking outside or selecting an item closes it.
// The CSS :hover path still works for quick fly-through on desktop;
// .open is the sticky fallback for when hover is unreliable (touch,
// narrow gap, trackpad drift).
(function () {
  'use strict';

  document.querySelectorAll('.nav-dropdown-trigger').forEach(function (btn) {
    btn.addEventListener('click', function (e) {
      e.preventDefault();
      var dd = btn.closest('.nav-dropdown');
      var wasOpen = dd.classList.contains('open');

      // Close all other dropdowns first
      document.querySelectorAll('.nav-dropdown.open').forEach(function (el) {
        el.classList.remove('open');
      });

      if (!wasOpen) dd.classList.add('open');
    });
  });

  // Close on outside click
  document.addEventListener('click', function (e) {
    if (!e.target.closest('.nav-dropdown')) {
      document.querySelectorAll('.nav-dropdown.open').forEach(function (el) {
        el.classList.remove('open');
      });
    }
  });

  // Close on Escape
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') {
      document.querySelectorAll('.nav-dropdown.open').forEach(function (el) {
        el.classList.remove('open');
      });
    }
  });

  // Close after selecting a menu item (navigation)
  document.querySelectorAll('.nav-dropdown-menu a').forEach(function (link) {
    link.addEventListener('click', function () {
      document.querySelectorAll('.nav-dropdown.open').forEach(function (el) {
        el.classList.remove('open');
      });
    });
  });
})();
