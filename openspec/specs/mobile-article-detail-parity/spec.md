## Requirements

### Requirement: Article detail response includes the cached summary and applied tags
The system SHALL include the article's cached summary (extractive and/or Claude, whichever exist) and its currently-applied tags in the response of `GET /api/v1/articles/:uid`, so the client doesn't need a second round-trip to render them.

#### Scenario: Article with a cached extractive summary
- **WHEN** an authenticated client requests an article that has an extractive summary
- **THEN** the response includes the summary text

#### Scenario: Article with applied tags
- **WHEN** an authenticated client requests an article the user has tagged
- **THEN** the response includes those tags

#### Scenario: Article with neither
- **WHEN** an authenticated client requests an article with no summary and no applied tags
- **THEN** the response is HTTP 200 with a null/empty summary and an empty tags array (not an error)

### Requirement: Articles are feedback-able (thumbs up/down)
The system SHALL expose `POST /api/v1/articles/:uid/feedback` accepting a `value` of `1`, `-1`, or `0`, matching the web app's 👍/👎 toggle (`0` clears existing feedback).

#### Scenario: Thumbs up
- **WHEN** an authenticated user sends `POST /api/v1/articles/:uid/feedback` with `value: 1`
- **THEN** the article's feedback for that user is recorded as `1`

#### Scenario: Clear feedback
- **WHEN** an authenticated user who previously gave feedback sends `value: 0`
- **THEN** the article's feedback for that user is cleared

#### Scenario: Invalid value rejected
- **WHEN** an authenticated user sends a `value` outside `{-1, 0, 1}`
- **THEN** the response is HTTP 400

### Requirement: Tags are applicable to and removable from an article
The system SHALL expose `POST /api/v1/articles/:uid/tags/:tag_id` (apply) and `DELETE /api/v1/articles/:uid/tags/:tag_id` (remove), scoped to tags the user owns.

#### Scenario: Apply a tag
- **WHEN** an authenticated user applies one of their own tags to an article
- **THEN** the tag appears in that article's applied-tags list

#### Scenario: Remove a tag
- **WHEN** an authenticated user removes a previously-applied tag from an article
- **THEN** it no longer appears in that article's applied-tags list

#### Scenario: Cannot apply another user's tag
- **WHEN** an authenticated user attempts to apply a tag id they don't own
- **THEN** the response is HTTP 404

### Requirement: iOS article detail shows full metadata and article-level actions
The iOS app SHALL show, on the article detail screen: a hero image (when present), feed name, author, relative published time, reading time or episode duration, a "Source" link opening the original article URL, 👍/👎 feedback controls, mute-author and mute-keyword shortcuts, tag chips (applied tags removable, unapplied tags one-tap-to-apply), the cached summary (when present), and a real mark-unread control (not just mark-read-on-open).

#### Scenario: View full metadata
- **WHEN** a signed-in user opens an article with a hero image, author, and cached summary
- **THEN** all of those are visible on the detail screen

#### Scenario: Open the source
- **WHEN** a signed-in user taps "Source"
- **THEN** the original article URL opens (in a browser sheet, not the in-app content renderer)

#### Scenario: Give feedback
- **WHEN** a signed-in user taps 👍 on an article
- **THEN** the button reflects the new state and a repeat tap clears it

#### Scenario: Mute from the article
- **WHEN** a signed-in user mutes the article's author
- **THEN** a mute rule is created (reusing the existing mute-rules endpoint) without leaving the article screen

#### Scenario: Manage tags from the article
- **WHEN** a signed-in user taps an unapplied tag chip
- **THEN** it becomes applied; tapping an applied chip removes it

#### Scenario: Mark unread
- **WHEN** a signed-in user marks a read article as unread
- **THEN** it shows as unread in article lists

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
