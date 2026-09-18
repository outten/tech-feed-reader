## Requirements

### Requirement: Article list supports a read-state filter
The system SHALL let `GET /api/v1/articles` accept a `state` query parameter (`unread`, `bookmarked`, `archived`, or `all`, default `all`), filtering results the same way the web app's `/articles?state=` and `/bookmarks` do.

#### Scenario: Filter to bookmarked articles
- **WHEN** an authenticated client requests `GET /api/v1/articles?state=bookmarked`
- **THEN** the response is HTTP 200 with only articles this user has bookmarked

#### Scenario: Filter to unread articles
- **WHEN** an authenticated client requests `GET /api/v1/articles?state=unread`
- **THEN** the response includes only articles with no read_state row or `read=0` for this user

### Requirement: Full-text search over subscribed articles
The system SHALL expose `GET /api/v1/search` accepting a `q` query parameter, returning full-text search results scoped to the user's subscriptions, matching the web app's `/search` behavior.

#### Scenario: Search with results
- **WHEN** an authenticated client requests `GET /api/v1/search?q=<term>` and matching articles exist in their subscriptions
- **THEN** the response is HTTP 200 with a JSON array of matching articles, ranked by relevance

#### Scenario: Empty query
- **WHEN** an authenticated client requests `GET /api/v1/search` with no `q` or an empty `q`
- **THEN** the response is HTTP 200 with an empty array (no error)

### Requirement: Tags are listable and filterable
The system SHALL expose `GET /api/v1/tags` (the user's tag rules) and support `GET /api/v1/articles?tag_id=<id>` to list articles matching a tag, mirroring the web app's `/tags` + tag-filtered `/articles`.

#### Scenario: List tags
- **WHEN** an authenticated client requests `GET /api/v1/tags`
- **THEN** the response is HTTP 200 with the user's tag rules (name, match_kind, match_value)

#### Scenario: Articles filtered by tag
- **WHEN** an authenticated client requests `GET /api/v1/articles?tag_id=<id>` for a tag they own
- **THEN** the response is HTTP 200 with articles matching that tag

### Requirement: Topics are browsable
The system SHALL expose `GET /api/v1/topics` (recent topic clusters) and `GET /api/v1/topics/:term` (articles for one topic term), mirroring the web app's `/topics` + `/topics/:term`.

#### Scenario: List recent topics
- **WHEN** an authenticated client requests `GET /api/v1/topics`
- **THEN** the response is HTTP 200 with a JSON array of topic clusters (term, article count)

#### Scenario: Articles for one topic
- **WHEN** an authenticated client requests `GET /api/v1/topics/:term` for an existing topic
- **THEN** the response is HTTP 200 with articles matching that topic term

### Requirement: iOS app exposes bookmarks, search, tags, and topics
The iOS app SHALL let a signed-in user view their bookmarked articles, search across their subscriptions, browse by tag, and browse by topic — reachable from the main navigation alongside the existing Feeds/Articles screens.

#### Scenario: View bookmarks
- **WHEN** a signed-in user opens the Bookmarks screen
- **THEN** their bookmarked articles are listed, sourced from `GET /api/v1/articles?state=bookmarked`

#### Scenario: Search
- **WHEN** a signed-in user enters a search term
- **THEN** matching articles from their subscriptions are shown, sourced from `GET /api/v1/search`

#### Scenario: Browse a tag
- **WHEN** a signed-in user selects one of their tags
- **THEN** articles matching that tag are shown

#### Scenario: Browse a topic
- **WHEN** a signed-in user selects a topic from the topics list
- **THEN** articles matching that topic are shown
