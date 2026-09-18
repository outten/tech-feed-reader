## Requirements

### Requirement: Curated feed catalog is browsable by category
The system SHALL expose `GET /api/v1/feed_catalog` returning the curated catalog grouped by category, each group carrying its display label, matching the web app's `/feeds` catalog browse section.

#### Scenario: List the catalog
- **WHEN** an authenticated client requests `GET /api/v1/feed_catalog`
- **THEN** the response is HTTP 200 with an array of `{ category, label, feeds: [{ url, title, blurb }, ...] }` groups

### Requirement: Recommended-for-you feeds
The system SHALL expose `GET /api/v1/feed_catalog/recommended` returning catalog entries scored against the user's current subscriptions, matching the web app's "Recommended for you" callout on `/feeds`.

#### Scenario: User with subscriptions gets recommendations
- **WHEN** an authenticated user with catalog-overlapping subscriptions requests `GET /api/v1/feed_catalog/recommended`
- **THEN** the response is HTTP 200 with catalog entries they aren't already subscribed to, ranked by relevance

#### Scenario: Cold start
- **WHEN** an authenticated user with no catalog-overlapping subscriptions requests `GET /api/v1/feed_catalog/recommended`
- **THEN** the response is HTTP 200 with an empty array (not an error)

### Requirement: Popular-by-type charts
The system SHALL expose `GET /api/v1/feeds/popular` accepting a `type` parameter (one of `news`, `sports`, `podcasts`, `nature`, `youtube`), returning the top subscribed-across-all-users feeds of that type, matching the web app's `/feeds` popular charts.

#### Scenario: Popular podcasts
- **WHEN** an authenticated client requests `GET /api/v1/feeds/popular?type=podcasts`
- **THEN** the response is HTTP 200 with the most-subscribed podcast feeds, ranked by subscriber count

### Requirement: Mute rules are manageable
The system SHALL expose `GET /api/v1/mute_rules` (list), `POST /api/v1/mute_rules` (add, body `{kind, value}`), and `DELETE /api/v1/mute_rules` (remove, query params `kind`+`value`), matching the web app's mute-rule management under Manage ▾.

#### Scenario: List mute rules
- **WHEN** an authenticated client requests `GET /api/v1/mute_rules`
- **THEN** the response is HTTP 200 with the user's mute rules (kind, value)

#### Scenario: Add a mute rule
- **WHEN** an authenticated client sends `POST /api/v1/mute_rules` with a valid kind/value
- **THEN** the response is HTTP 201 and the rule appears in a subsequent list call
- **THEN** articles matching that rule are subsequently excluded from article-list responses (existing `ArticlesStore` behavior — unchanged, just now reachable from a native client)

#### Scenario: Remove a mute rule
- **WHEN** an authenticated client sends `DELETE /api/v1/mute_rules?kind=<kind>&value=<value>` for an existing rule
- **THEN** the response is HTTP 200 and the rule no longer appears in a subsequent list call

### Requirement: iOS app exposes catalog browse, recommendations, popular charts, and mute rules
The iOS app SHALL let a signed-in user browse the curated catalog by category and subscribe with one tap, see recommended-for-you feeds, see popular-by-type charts, and manage their mute rules — reachable from the Feeds section of the sidebar.

#### Scenario: Browse and subscribe from the catalog
- **WHEN** a signed-in user browses a catalog category and taps a feed
- **THEN** they become subscribed to that feed, sourced from the existing `POST /api/v1/subscriptions` endpoint

#### Scenario: View recommended feeds
- **WHEN** a signed-in user with existing subscriptions opens the catalog screen
- **THEN** a "Recommended for you" section shows catalog entries relevant to their subscriptions

#### Scenario: Manage mute rules
- **WHEN** a signed-in user adds a keyword mute rule
- **THEN** it appears in their mute rules list and future article-list fetches exclude matching articles
