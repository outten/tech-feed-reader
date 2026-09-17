## ADDED Requirements

### Requirement: League detail falls back to catalog data instead of 404ing
`GET /api/v1/sports/leagues/:slug` SHALL return a valid (if data-sparse) response for a league that exists in the static catalog but has no `sports_leagues` row yet (not-yet-followed/synced — the common case for tournaments), instead of HTTP 404. This matches the existing fallback behavior of `GET /api/v1/sports/teams/:slug`.

#### Scenario: Catalog-only tournament
- **WHEN** an authenticated client requests `GET /api/v1/sports/leagues/:slug` for a tournament that exists in `SportsCatalog` but has never been followed or synced
- **THEN** the response is HTTP 200 with the catalog's league info, empty `standings`/`upcoming`/`recent_finals`/`teams_by_id`, and `followed: false`

#### Scenario: Truly unknown slug still 404s
- **WHEN** an authenticated client requests `GET /api/v1/sports/leagues/:slug` for a slug that exists in neither the database nor the catalog
- **THEN** the response is HTTP 404

#### Scenario: Synced league is unaffected
- **WHEN** an authenticated client requests `GET /api/v1/sports/leagues/:slug` for a league that already has a `sports_leagues` row
- **THEN** the response is unchanged from today — full standings/matches from the database

### Requirement: Tennis ATP/WTA rankings are available on mobile
The system SHALL expose `GET /api/v1/sports/tennis/rankings` (param `limit` — default 50, clamped to `[1, 150]`), returning both `atp` and `wta` lists, backed by the same `SportsPlayersStore.top_ranked`/`refresh_if_stale!` the web `/sports/tennis` route uses, including each player's follow state for the caller.

#### Scenario: Rankings include follow state
- **WHEN** an authenticated client requests `GET /api/v1/sports/tennis/rankings`
- **THEN** the response includes ATP and WTA player lists ordered by rank, plus the caller's followed player slugs

### Requirement: iOS Sports screens show team/player images
`MatchRow`, `SportsHomeView`'s Followed Teams list, `SportsLeagueDetailView`'s Teams section, and `SportsTeamDetailView`'s header SHALL render each team's logo (`imageUrl`) when present, matching the web app's team-logo treatment across its sports pages.

#### Scenario: Match row shows logos
- **WHEN** a signed-in user views a match with known home/away teams that have logos
- **THEN** both team logos appear in the match row

#### Scenario: Missing logo degrades gracefully
- **WHEN** a team has no `imageUrl`
- **THEN** its row/header shows correctly with no broken-image placeholder

### Requirement: iOS has a discoverable tennis rankings screen with inline follow
The iOS app SHALL provide a Tennis Rankings screen (ATP/WTA lists, headshot, rank, name, and an inline follow toggle per row), reachable directly from the Sports home screen — not only through a team's player list.

#### Scenario: Follow a player from the rankings list
- **WHEN** a signed-in user opens Tennis Rankings and taps the follow toggle on a player row
- **THEN** that player becomes followed without leaving the rankings list, and subsequently appears in Sports' "Followed Players" section
