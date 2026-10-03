## MODIFIED Requirements

### Requirement: Team, league, and player detail
The system SHALL expose `GET /api/v1/sports/teams/:slug`, `/leagues/:slug`, and `/players/:slug` returning that entity's profile, standings/upcoming/recent-results (where applicable), mentioning articles, and the user's follow state — matching the web app's `/sports/team/:slug`, `/sports/league/:slug`, `/sports/player/:slug`. Team and league detail both include a `teams_by_id` lookup (keyed by team id) covering every team referenced in `upcoming`/`recent_finals`, so a client can resolve opponent names without a separate round-trip per match.

#### Scenario: Team detail with DB data
- **WHEN** an authenticated client requests a synced team's detail
- **THEN** the response includes standings, upcoming matches, recent results, and mentioning articles

#### Scenario: Team detail's upcoming/recent-results matches resolve opponent names
- **WHEN** an authenticated client requests a synced team's detail and it has upcoming or recently-finished matches
- **THEN** the response's `teams_by_id` includes an entry for every opponent team id referenced by those matches, keyed by that team's id

#### Scenario: Team detail, catalog-only (not yet synced)
- **WHEN** an authenticated client requests a catalog team not yet in the database
- **THEN** the response is HTTP 200 with basic catalog info and empty standings/matches/mentions (not a 404)

#### Scenario: League detail
- **WHEN** an authenticated client requests a league's detail
- **THEN** the response includes standings grouped by group name, upcoming matches, and recent results

#### Scenario: Player detail materializes catalog players
- **WHEN** an authenticated client requests a catalog "notable player" chip's detail for the first time
- **THEN** the player is materialized into `sports_players` and the response is HTTP 200
