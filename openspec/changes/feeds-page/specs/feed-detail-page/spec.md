## ADDED Requirements

### Requirement: Per-feed content page
The system SHALL provide a page at `/feeds/:feed_id` that lists recent content for a single subscribed feed, with engage actions appropriate to the content type.

#### Scenario: Authenticated user views a subscribed feed
- **WHEN** a signed-in user visits `/feeds/123` and feed 123 is in their subscriptions
- **THEN** the response SHALL be HTTP 200 with the feed title and a list of recent articles/episodes

#### Scenario: Unsubscribed or unknown feed returns 404
- **WHEN** a user visits `/feeds/999` and either the feed does not exist or the user is not subscribed
- **THEN** the response SHALL be HTTP 404

#### Scenario: Audio episode shows Listen action
- **WHEN** an article has a non-empty `audio_url`
- **THEN** the page SHALL render a "Listen" link to `/article/:uid`

#### Scenario: YouTube video shows Watch action
- **WHEN** an article has no audio_url but its URL contains `youtube.com` or `youtu.be`
- **THEN** the page SHALL render a "Watch" link opening the external URL in a new tab

#### Scenario: Text article shows Read action
- **WHEN** an article has no audio_url and no YouTube URL
- **THEN** the page SHALL render a "Read" link to `/article/:uid`

### Requirement: Feeds nav link
The primary navigation SHALL include a "Feeds" link to `/feeds` that is active when the current path is `/feeds` or begins with `/feeds/`.

#### Scenario: Nav link is active on feeds index
- **WHEN** the user is on `/feeds`
- **THEN** the "Feeds" nav link SHALL have the `active` CSS class

#### Scenario: Nav link is active on per-feed page
- **WHEN** the user is on `/feeds/123`
- **THEN** the "Feeds" nav link SHALL have the `active` CSS class

### Requirement: Feed list links to per-feed page
The subscriptions list on `/feeds` SHALL render each feed title as a link to `/feeds/:feed_id`.

#### Scenario: Feed title links to content page
- **WHEN** the user views `/feeds` and has subscribed feeds
- **THEN** each feed title SHALL be a link to `/feeds/<feed_id>`
