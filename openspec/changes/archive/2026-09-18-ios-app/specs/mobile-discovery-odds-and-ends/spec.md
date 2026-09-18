## ADDED Requirements

### Requirement: Bus mode lists short podcast episodes
The system SHALL expose `GET /api/v1/articles/bus` returning podcast episodes whose duration is at or under a `max_minutes` param (default 15, clamped to `[1, 90]`, matching the web `/bus` route's constants), capped at 25 results.

#### Scenario: Default cutoff
- **WHEN** an authenticated client requests `GET /api/v1/articles/bus` with no `max_minutes`
- **THEN** only podcast episodes with `audio_duration_seconds <= 900` are returned

#### Scenario: Custom cutoff is clamped
- **WHEN** an authenticated client requests `GET /api/v1/articles/bus?max_minutes=500`
- **THEN** the effective cutoff is clamped to 90 minutes

### Requirement: I Feel Lucky returns a random cross-type sample
The system SHALL expose `GET /api/v1/articles/lucky` returning a random sample (up to 50) of the caller's subscribed articles, respecting mute rules — matching the web `/lucky` route.

#### Scenario: Returns articles
- **WHEN** an authenticated client with subscribed feeds requests `GET /api/v1/articles/lucky`
- **THEN** the response is HTTP 200 with a non-empty array (when articles exist)

### Requirement: Feeds support refresh-now and relevance-weight adjustment
The system SHALL expose `POST /api/v1/feeds/:id/refresh` (enqueues an immediate fetch of that feed, matching the web `/api/refresh/:feed_id` route) and `POST /api/v1/feeds/:id/weight` (body `direction` ∈ `up`/`down`/`reset`, matching the web per-feed weighting), and `GET /api/v1/feeds` includes each feed's current weight (see `mobile-api` spec).

#### Scenario: Refresh a feed
- **WHEN** an authenticated client sends `POST /api/v1/feeds/:id/refresh` for a feed they're subscribed to
- **THEN** the response is HTTP 200 and a refresh is enqueued

#### Scenario: Adjust weight
- **WHEN** an authenticated client sends `POST /api/v1/feeds/:id/weight` with `direction: up`
- **THEN** the response includes the new weight, increased by the standard step

### Requirement: Tags support rule creation and deletion
The system SHALL expose `POST /api/v1/tags` (body `name`, `match_kind`, `match_value` — creates a tag rule and immediately backfills it against existing articles, matching the web `/tags` route) and `DELETE /api/v1/tags/:id` (removes a tag rule the caller owns).

#### Scenario: Create a tag rule
- **WHEN** an authenticated client sends `POST /api/v1/tags` with a valid name/kind/value
- **THEN** the response is HTTP 200/201 with the created tag, and it appears in a subsequent `GET /api/v1/tags`

#### Scenario: Invalid kind rejected
- **WHEN** an authenticated client sends `POST /api/v1/tags` with a `match_kind` outside the supported set
- **THEN** the response is HTTP 400

#### Scenario: Delete a tag rule
- **WHEN** an authenticated client sends `DELETE /api/v1/tags/:id` for a tag they own
- **THEN** the response is HTTP 200 and it no longer appears in `GET /api/v1/tags`

### Requirement: First-run onboarding mirrors the web's topic-chip flow
The system SHALL expose `GET /api/v1/onboarding/chips` (returns the curated topic chips: key, label, blurb, emoji) and `POST /api/v1/onboarding/subscribe` (body `topics: [...]` — subscribes the caller to each selected topic's curated starter feeds, matching the web `/welcome` flow).

#### Scenario: List chips
- **WHEN** an authenticated client requests `GET /api/v1/onboarding/chips`
- **THEN** the response includes the same curated topics the web `/welcome` page offers

#### Scenario: Subscribe via chips
- **WHEN** an authenticated client posts `POST /api/v1/onboarding/subscribe` with `topics: ["technology"]`
- **THEN** the caller is subscribed to that topic's curated starter feeds

### Requirement: Account data is exportable
The system SHALL expose `GET /api/v1/account/export` returning the same JSON payload as the web `/account/export.json` route (`AccountExport.for_user`), for the iOS app to offer via a native share sheet.

#### Scenario: Export includes account data
- **WHEN** an authenticated client requests `GET /api/v1/account/export`
- **THEN** the response is HTTP 200 with a JSON export of their account data

### Requirement: iOS surfaces bus mode, lucky, per-feed controls, tag management, onboarding, and export
The iOS app SHALL provide: a Bus Mode screen (episode list + max-minutes control), an "I Feel Lucky" screen, per-feed refresh-now and weight controls (reachable from a subscribed feed's article list), tag rule creation (with a form: name/kind/value) and deletion in the existing Tags screen, a first-run Welcome screen (topic chips → subscribe) shown when the account has zero subscribed feeds, and an "Export My Data" action in Account that shares the exported JSON via the system share sheet.

#### Scenario: Bus mode adjustable cutoff
- **WHEN** a signed-in user opens Bus Mode and changes the max-minutes control
- **THEN** the episode list refreshes to the new cutoff

#### Scenario: Feed weight control
- **WHEN** a signed-in user viewing one of their feeds taps "Boost" (up)
- **THEN** that feed's weight increases and the change persists across app relaunch

#### Scenario: Create and delete a tag
- **WHEN** a signed-in user adds a new tag rule from the Tags screen
- **THEN** it appears in the list and can subsequently be removed

#### Scenario: First-run welcome
- **WHEN** a signed-in user with zero subscribed feeds opens the app
- **THEN** they see the Welcome screen instead of an empty Home dashboard

#### Scenario: Export shares a file
- **WHEN** a signed-in user taps "Export My Data" in Account
- **THEN** the system share sheet opens with the exported JSON, ready to save or send
