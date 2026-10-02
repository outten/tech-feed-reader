## ADDED Requirements

### Requirement: Article detail header and body scroll as one unit
The iOS app's article detail screen SHALL present its metadata header and its body content inside a single scrolling region, so scrolling the body also scrolls the header out of view rather than leaving it pinned. This applies regardless of content type (HTML, plain text, or YouTube embed) and on every entry point into article detail.

#### Scenario: Scrolling an HTML article moves the header
- **WHEN** a signed-in user scrolls down on an article whose body is HTML content
- **THEN** the metadata header scrolls away with the body, and continuing to scroll reveals more of the article content

#### Scenario: Scrolling a plain-text article moves the header
- **WHEN** a signed-in user scrolls down on an article with plain-text content (no HTML)
- **THEN** the metadata header scrolls away with the body in the same way

#### Scenario: Scrolling a YouTube article moves the header
- **WHEN** a signed-in user scrolls down on a YouTube article (video + caption text)
- **THEN** the metadata header scrolls away with the body; the video itself keeps its fixed aspect ratio

#### Scenario: HTML content reflows correctly after images finish loading
- **WHEN** an HTML article contains images that finish loading after the page's initial render
- **THEN** the scrollable area's height reflects the article's true final height — no content is clipped or cut off

#### Scenario: Rotating the device keeps content correctly sized
- **WHEN** a signed-in user rotates an iPad between portrait and landscape while viewing an HTML article
- **THEN** the body's rendered height adjusts correctly for the new width — no clipped or cut-off content

#### Scenario: Toolbar actions remain available regardless of scroll position
- **WHEN** a signed-in user has scrolled the header out of view
- **THEN** the play/read/bookmark/archive toolbar actions are still reachable (unaffected by body scroll position, matching their existing pinned behavior)
