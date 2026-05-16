/* Press "/" anywhere outside a text field to jump to /search.
 *
 * The search page's input has `autofocus`, so a single keystroke
 * takes the user from any page → focused search box. Ignored when
 * the focus is already in an input / textarea / contenteditable so
 * the key still types in those contexts.
 */
(function () {
  'use strict';

  document.addEventListener('keydown', function (e) {
    if (e.key !== '/') return;
    if (e.metaKey || e.ctrlKey || e.altKey) return;

    var t = e.target;
    if (!t) return;
    var tag = (t.tagName || '').toLowerCase();
    if (tag === 'input' || tag === 'textarea' || tag === 'select') return;
    if (t.isContentEditable) return;

    if (window.location.pathname === '/search') return;

    e.preventDefault();
    window.location.href = '/search';
  });
})();
