## Requirements

### Requirement: Sports catalog is browsable
The system SHALL expose `GET /api/v1/sports` (list of sports with metadata), `GET /api/v1/sports/:sport_slug/leagues` (leagues in a sport), and `GET /api/v1/sports/:sport_slug/:league_slug/teams` (teams in a league — falling back to synced DB teams for provider-backed leagues whose catalog entry ships no static team list), matching the web app's `/sports/manage` drill-down.

#### Scenario: List sports
- **WHEN** an authenticated client requests `GET /api/v1/sports`
- **THEN** the response is HTTP 200 with every catalog sport's slug, name, emoji, region, and blurb

#### Scenario: List leagues in a sport
- **WHEN** an authenticated client requests `GET /api/v1/sports/football/leagues`
- **THEN** the response is HTTP 200 with that sport's leagues

#### Scenario: List teams in a league
- **WHEN** an authenticated client requests `GET /api/v1/sports/football/nfl/teams`
- **THEN** the response is HTTP 200 with that league's teams

### Requirement: Teams, leagues, and players are followable
The system SHALL expose `POST`/`DELETE /api/v1/sports/teams/follow`, `/leagues/follow`, and `/players/follow` (body/query `slug`), materializing a catalog entry into the DB on follow exactly as the web routes do, matching the web app's follow/unfollow actions.

#### Scenario: Follow a catalog-only team
- **WHEN** an authenticated user follows a team that exists in the catalog but has no DB row yet
- **THEN** the team (and its league) is upserted into the database
- **THEN** the follow is recorded and the team subsequently appears in the user's followed teams

#### Scenario: Unfollow
- **WHEN** an authenticated user unfollows a previously-followed team
- **THEN** it no longer appears in their followed teams

#### Scenario: Follow a player
- **WHEN** an authenticated user follows a player who already has a `sports_players` row (e.g. after viewing their detail page)
- **THEN** the follow is recorded

### Requirement: Team, league, and player detail
The system SHALL expose `GET /api/v1/sports/teams/:slug`, `/leagues/:slug`, and `/players/:slug` returning that entity's profile, standings/upcoming/recent-results (where applicable), mentioning articles, and the user's follow state — matching the web app's `/sports/team/:slug`, `/sports/league/:slug`, `/sports/player/:slug`.

#### Scenario: Team detail with DB data
- **WHEN** an authenticated client requests a synced team's detail
- **THEN** the response includes standings, upcoming matches, recent results, and mentioning articles

#### Scenario: Team detail, catalog-only (not yet synced)
- **WHEN** an authenticated client requests a catalog team not yet in the database
- **THEN** the response is HTTP 200 with basic catalog info and empty standings/matches/mentions (not a 404)

#### Scenario: League detail
- **WHEN** an authenticated client requests a league's detail
- **THEN** the response includes standings grouped by group name, upcoming matches, and recent results

#### Scenario: Player detail materializes catalog players
- **WHEN** an authenticated client requests a catalog "notable player" chip's detail for the first time
- **THEN** the player is materialized into `sports_players` and the response is HTTP 200

### Requirement: Followed-sports overview with live matches
The system SHALL expose `GET /api/v1/sports/overview` returning the user's followed teams/leagues/players and all currently-live matches, matching the core of the web app's `/sports` overview.

#### Scenario: Overview with follows
- **WHEN** an authenticated user with followed teams requests `GET /api/v1/sports/overview`
- **THEN** the response includes those teams and any currently-live matches

### Requirement: iOS app supports sports browse, follow, and detail
The iOS app SHALL let a signed-in user browse the sports catalog, follow/unfollow teams/leagues/players, view team/league/player detail, and see a followed-sports overview with live matches.

#### Scenario: Browse and follow
- **WHEN** a signed-in user drills into a sport → league → team and taps follow
- **THEN** the team appears in their sports overview

#### Scenario: View detail
- **WHEN** a signed-in user opens a followed team's detail
- **THEN** standings, upcoming matches, recent results, and mentioning articles are shown
