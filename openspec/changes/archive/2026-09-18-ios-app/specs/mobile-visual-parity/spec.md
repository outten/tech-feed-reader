## ADDED Requirements

### Requirement: Article list endpoint supports a youtube kind filter
`GET /api/v1/articles` SHALL accept `kind=youtube` (in addition to the existing `kind=podcast`), matching the web app's YouTube-video kind filter (articles whose feed URL matches the YouTube channel-feed pattern).

#### Scenario: YouTube-only filter
- **WHEN** an authenticated client requests `GET /api/v1/articles?kind=youtube`
- **THEN** only articles from a YouTube channel feed are returned

### Requirement: Podcasts and YouTube show a cover-art grid for subscribed shows/channels
The iOS Podcasts and YouTube screens SHALL each show their subscribed shows/channels as a grid of cards with cover art (falling back gracefully when no image is available), title, and a meta line (episode/video count + latest date) — mirroring the web app's `.podcast-show-card` grid, which both screens already share.

#### Scenario: Shows render as an image grid
- **WHEN** a signed-in user with subscribed podcasts opens the Podcasts screen
- **THEN** subscribed shows appear as a grid of cover-art cards, not a plain text list

#### Scenario: Channels render as an image grid
- **WHEN** a signed-in user with subscribed YouTube channels opens the YouTube screen
- **THEN** subscribed channels appear as a grid of cover-art cards, using the same card component as Podcasts

### Requirement: Recent-items lists show image-led cards
Podcasts' "Recent Episodes", Comics' "Recent Panels", and the NPR/PBS article lists SHALL render each item as an image-led card (leading thumbnail, feed name, relative date, duration badge when applicable, title, short excerpt) instead of a bare title+date row — mirroring the web app's `.podcast-card` component, which all four of these web pages already share.

#### Scenario: Podcast episode shows a thumbnail
- **WHEN** a signed-in user opens Podcasts and a recent episode has an image
- **THEN** that episode's row shows the thumbnail alongside its title and metadata

#### Scenario: No image degrades gracefully
- **WHEN** an item has no available image
- **THEN** the card still renders correctly with just its text content, no broken-image placeholder

### Requirement: YouTube has a Recent Videos grid
The iOS YouTube screen SHALL show a "Recent Videos" section — a grid of 16:9-thumbnail cards (title, channel name, relative date) drawn from `kind=youtube` articles across all subscribed channels — mirroring the web app's `.youtube-video-card` grid. This section does not exist on iOS today (only the channel list does).

#### Scenario: Recent videos grid appears
- **WHEN** a signed-in user with subscribed YouTube channels and recent videos opens the YouTube screen
- **THEN** a "Recent Videos" grid of thumbnail cards appears above the channels grid, matching the web page's section order

#### Scenario: Thumbnail derived client-side
- **WHEN** a video article has no explicit `image_url`
- **THEN** its thumbnail is derived from the video ID (`https://i.ytimg.com/vi/<id>/hqdefault.jpg`), matching the web app's `youtube_thumbnail_url` fallback
