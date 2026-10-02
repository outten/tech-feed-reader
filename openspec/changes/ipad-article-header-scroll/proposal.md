## Why

On the article detail screen, the metadata header (hero image, feed/author/time line, feedback buttons, mute shortcuts, tag chips, cached summary) is a fixed block above a `Divider()`, with only the body content scrolling underneath it (`ArticleDetailView.swift`'s `VStack { header; Divider(); content }`). On iPhone portrait this is a minor inconvenience; on iPad — especially landscape, where the window is wide and short — the fixed header plus the navigation bar/toolbar can consume a large share of the visible height before any article text is reachable, and it stays pinned there even once the user has scrolled past the point of caring about the metadata. Making the header scroll away with the body reclaims that space.

## What Changes

- The header and the article body become one continuously-scrolling unit instead of a fixed header above an independently-scrolling body.
- For HTML article content (the common case, rendered via `ArticleContentView`'s `WKWebView`), this requires making the web view self-sizing: disable its own internal scrolling, measure its rendered content height, and size it exactly to that height so it can sit inside the same outer `ScrollView` as the header without the two scroll regions fighting each other. This is the one piece with real implementation risk — flagged in design.md.
- Plain-text and YouTube-embed article content (the two other branches in `ArticleDetailView.content`) move into the same outer `ScrollView` too — simpler, since neither currently depends on WKWebView's own scrolling.
- **No change** to what the header displays, the toolbar (play/read/bookmark/archive buttons stay pinned via `.toolbar`, which is independent of body scrolling), or any `/api/v1/*` endpoint — this is purely a client-side layout change to one shared view.
- `ArticleDetailView` is shared by every entry point into article detail (search, home, bus mode, articles list, reading river, podcasts, YouTube, sports, stocks, triage) — the fix lands once and applies everywhere, not just on iPad. iPhone portrait gains the same unified scroll; the problem is just less visually pressing there, which is why the user reported it from the iPad specifically.

## Capabilities

### Modified Capabilities
- `mobile-article-detail-parity`: adds a requirement that the article detail screen's header and body scroll as a single unit, alongside the existing "shows full metadata and article-level actions" requirement (which stays unchanged — this doesn't touch what's shown, only how it scrolls).

## Impact

- **iOS only**: `ios/TechFeedReader/Views/ArticleDetailView.swift` (restructure `body` to a single `ScrollView`), `ios/TechFeedReader/Views/ArticleContentView.swift` (disable internal WKWebView scrolling, add content-height measurement and reporting back to SwiftUI).
- No backend changes, no new/changed API endpoints.
- No change to the toolbar, navigation title, or any sheet/alert presentation already on this screen.
