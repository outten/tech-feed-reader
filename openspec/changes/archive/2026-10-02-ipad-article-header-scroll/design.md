## Context

`ArticleDetailView.body` is currently:
```swift
VStack(spacing: 0) {
    header       // fixed metadata block — hero image, feed/author/time, feedback, mute, tags, summary
    Divider()
    content      // independently scrolling body
}
```
`content` has three branches: YouTube embed + a `ScrollView`-wrapped `Text`, HTML via `ArticleContentView` (a bare `WKWebView` wrapper, `.frame(maxWidth: .infinity, maxHeight: .infinity)`, scrolling internally), or plain text via a `ScrollView`-wrapped `Text`. The HTML branch is the common case (most articles have `content_html`) and the only one that doesn't already use a SwiftUI `ScrollView` — `ArticleContentView`'s own code comment already documents why: *"WKWebView reports no intrinsic content size in SwiftUI — without an explicit frame it collapses to zero height and renders nothing."* That's the one piece of real work here; the other two branches just need to move into a shared outer `ScrollView`.

## Goals / Non-Goals

**Goals:**
- Header and body scroll together as one unit, for all three content branches, reclaiming vertical space on iPad landscape (and improving iPhone too, since the view is shared).
- No visible change to what the header shows or how the toolbar behaves.

**Non-Goals:**
- No change to HTML sanitization, article content itself, or the toolbar's pinned actions.
- No "collapsing header" animation/parallax effect (e.g. a header that shrinks as you scroll, iOS-Mail-style) — just a single continuous scroll. A fancier collapsing-header treatment is a separate, purely-visual follow-up if wanted later, not bundled into this fix.

## Decisions

### 1. One outer `ScrollView` wrapping header + content, all three branches
```swift
ScrollView {
    VStack(spacing: 0) {
        header
        Divider()
        content   // sized appropriately per branch, below
    }
}
```
Replaces the current fixed-`VStack`-above-independently-scrolling-`content` structure. The toolbar (`.toolbar { ToolbarItemGroup... }`) is attached to the view hierarchy outside this `ScrollView`, not inside it, so it's unaffected — it already behaves like a pinned nav-bar accessory today and continues to.

### 2. Self-sizing `ArticleContentView`: disable internal scroll, measure height via `ResizeObserver`, report through a binding
`ArticleContentView` gains a `@Binding var contentHeight: CGFloat` and:
- `webView.scrollView.isScrollEnabled = false` in `makeUIView` — the web view no longer scrolls itself; the outer `ScrollView` does.
- Injected JS (via `WKUserScript` or a script tag in the loaded HTML) sets up a `ResizeObserver` on `document.body` that posts `document.body.scrollHeight` through a `WKScriptMessageHandler` whenever it changes — not just once at `didFinish`. **Why a `ResizeObserver` over a single post-`didFinish` measurement**: images inside article content often finish decoding and reflow the page *after* `didFinish` fires (navigation "finishes" when the initial HTML parse completes, not when every image has loaded) — a one-shot measurement would under-report height and clip content. A `ResizeObserver` also naturally re-fires on rotation/width changes (the web view's width tracks the outer container via `.frame(maxWidth: .infinity)`, only height is pinned to the measured value), so portrait↔landscape and Split View width changes stay correct without separate handling.
- The view applies `.frame(height: contentHeight)` (with a sane minimum, e.g. 1pt, before the first measurement lands, to avoid the original zero-height collapse) instead of `maxHeight: .infinity`.

**Alternative considered**: measure once in `webView(_:didFinish:)` via a single `evaluateJavaScript("document.body.scrollHeight")` call. Rejected — doesn't account for post-load image reflow (the exact zero-height-collapse failure mode this screen has already hit once before, per the existing code comment), and doesn't handle rotation.

**Alternative considered**: keep the WKWebView's own scrolling and instead make the *header* draggable/collapsible via a custom gesture synced to the web view's internal scroll offset (reading WKWebView's `scrollView` delegate). Rejected — meaningfully more code (bridging two independent scroll mechanisms, keeping them in sync, handling overscroll/bounce at both ends) for the same visible result as one shared `ScrollView`; not justified for this problem.

### 3. YouTube and plain-text branches: move inside the shared `ScrollView`, drop their own inner `ScrollView`
Both currently wrap their `Text` in their own `ScrollView`; that inner `ScrollView` is removed since the outer one now covers them. The YouTube video itself keeps its fixed `16/9` aspect-ratio frame (it was never independently scrollable — only the text below it was).

## Risks / Trade-offs

- **[Risk] `ResizeObserver` + `WKScriptMessageHandler` round-trip adds a brief delay before the web view reaches its true height** (a frame or two where it's still at the fallback minimum height) → Mitigation: acceptable, matches the existing behavior's own brief "collapsed to zero" window before `didFinish`; not a regression, and visually it's a sub-second content reflow similar to any lazy-loading web page.
- **[Risk] A very long article (many large images) now renders its entire HTML content in one non-virtualized `WKWebView` frame inside a `ScrollView`, rather than a self-scrolling web view** → Mitigation: not actually a new risk — the web view already renders the complete DOM today (WKWebView doesn't virtualize/recycle content regardless of who owns scrolling), so memory/CPU cost is unchanged; only which component owns the scroll gesture changes.
- **[Trade-off] No collapsing/parallax header animation** — explicitly out of scope (see Non-Goals) to keep this a contained layout fix rather than a visual redesign.

## Open Questions

None — this is a self-contained client-side layout change with no backend/API surface and no ambiguous requirements.
