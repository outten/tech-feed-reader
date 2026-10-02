## 1. Self-sizing ArticleContentView

- [x] 1.1 Add a `@Binding var contentHeight: CGFloat` to `ArticleContentView`.
- [x] 1.2 Set `webView.scrollView.isScrollEnabled = false` in `makeUIView`.
- [x] 1.3 Inject a `ResizeObserver` on `document.body` (via a `<script>` in the loaded HTML or a `WKUserScript`) that posts `document.body.scrollHeight` through a `WKScriptMessageHandler` whenever it changes.
- [x] 1.4 Add the message handler to the `Coordinator`, updating the bound `contentHeight` on each message.
- [x] 1.5 Replace `.frame(maxWidth: .infinity, maxHeight: .infinity)` with `.frame(height: max(contentHeight, 1))` (minimum 1pt before the first measurement lands).

## 2. Unify ArticleDetailView into one scrolling region

- [x] 2.1 Add `@State private var htmlContentHeight: CGFloat = 1` to `ArticleDetailView`, pass as the new binding into `ArticleContentView`.
- [x] 2.2 Restructure `body` to wrap `header`, `Divider()`, and `content` in a single outer `ScrollView` (replacing the current fixed-header-above-scrolling-content `VStack`).
- [x] 2.3 Remove the inner `ScrollView` from the plain-text content branch (now covered by the outer one).
- [x] 2.4 Remove the inner `ScrollView` from the YouTube content branch's caption text (now covered by the outer one); keep the video's fixed `16/9` aspect-ratio frame.
- [x] 2.5 Confirm the `.toolbar` modifier and its actions are unaffected (they're attached to the view, not inside the new `ScrollView`).

## 3. Verification

- [ ] 3.1 Build (Debug) and install on iPad Pro 11" (M5) Simulator in landscape; open an HTML article with several paragraphs and at least one image, confirm header scrolls away with the body and no content is clipped after images load.
- [ ] 3.2 Rotate portrait↔landscape while mid-article; confirm no clipped/cut-off content after the rotation (ResizeObserver reflow).
- [ ] 3.3 Open a plain-text article and a YouTube article; confirm both scroll header+body together.
- [ ] 3.4 Confirm toolbar actions (play/read/bookmark/archive) still work correctly regardless of scroll position.
- [ ] 3.5 Spot-check on iPhone 17 Simulator too, since `ArticleDetailView` is shared — confirm no regression there.
- [ ] 3.6 Screenshot both simulators for a visual sanity check; pause for explicit manual-verification approval before committing, per the standing UI-change rule.

## 4. Wrap-up

- [ ] 4.1 `openspec archive` this change once verified.
