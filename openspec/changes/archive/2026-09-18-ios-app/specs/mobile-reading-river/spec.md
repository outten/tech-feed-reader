## ADDED Requirements

### Requirement: Article list endpoint supports a kind filter and relevance sort
`GET /api/v1/articles` SHALL accept a `kind` query param (`podcast` or unset/`all`, matching the web app's `/articles?kind=podcast`) and a `sort` query param (`relevance` or unset/chronological). When `sort=relevance`, the response SHALL be produced by the personalized For-You ranker (`Recommendation::ForYou.score_window`), and the effective state filter SHALL be forced to `unread` regardless of the `state` param, matching the web `/articles?sort=relevance` route.

#### Scenario: Podcast-only filter
- **WHEN** an authenticated client requests `GET /api/v1/articles?kind=podcast`
- **THEN** only articles with a non-null `audio_url` are returned

#### Scenario: Relevance sort forces unread
- **WHEN** an authenticated client requests `GET /api/v1/articles?sort=relevance&state=all`
- **THEN** the response contains only unread articles, ranked by the For-You scorer rather than published-date order

#### Scenario: Default behavior unchanged
- **WHEN** an authenticated client requests `GET /api/v1/articles` with no `kind` or `sort` param
- **THEN** the response is unchanged from the pre-Phase-12 chronological, all-kinds behavior

### Requirement: iOS has an "All Articles" reading river screen
The iOS app SHALL provide an "All Articles" screen, reachable from the sidebar, showing every subscribed article (not scoped to one feed/tag/topic) with controls for the state filter (all/unread/bookmarked/archived), the kind filter (all/podcasts only), the topic filter (all/a specific topic), and a chronological/relevance sort toggle, plus page-based pagination so the corpus isn't capped at one page.

#### Scenario: Sidebar entry exists
- **WHEN** a signed-in user opens the sidebar
- **THEN** an "All Articles" entry is present under Library, above the per-feed list

#### Scenario: Filters narrow the list
- **WHEN** a signed-in user sets the state filter to "Unread" and the kind filter to "Podcasts"
- **THEN** the list shows only unread podcast episodes

#### Scenario: Relevance sort
- **WHEN** a signed-in user switches the sort control to "For You"
- **THEN** the list re-fetches using `sort=relevance` and shows unread articles ranked by the personalized scorer

#### Scenario: Load more
- **WHEN** a signed-in user scrolls to the end of a full page of results
- **THEN** the next page loads and appends to the list without losing scroll position or duplicating rows
