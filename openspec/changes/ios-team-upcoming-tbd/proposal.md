## Why

On a team's detail screen in the iOS app, the "Upcoming" (and "Recent Results") match rows show "TBD @ TBD" instead of real opponent names. Root cause: `GET /api/v1/sports/teams/:slug` returns `upcoming`/`recent_finals` as raw `sports_matches` rows (`home_team_id`/`away_team_id` integers only, no team names), and iOS's `SportsTeamDetailView` renders them via `MatchRow(match: $0)` with no `teamsById` lookup map to resolve those ids against — `MatchRow` falls back to "TBD" when it can't resolve a team. The web app's equivalent page (`/sports/team/:slug`) works because its route separately builds a `@teams_by_id` lookup and the view resolves names from it. The sibling mobile route `GET /api/v1/sports/leagues/:slug` already does this correctly (returns a scoped `teams_by_id`, and iOS's `SportsLeagueDetailView` already passes it to `MatchRow`) — this is the same fix, applied to the one route that's missing it.

## What Changes

- `GET /api/v1/sports/teams/:slug` additionally returns `teams_by_id`, built the same way the leagues route already does: collect the home/away team ids referenced by `upcoming` + `recent_finals`, look them up in one scoped query (`SportsTeamsStore.find_many`, not a full-table scan — matching `build_teams_by_id_for_matches`'s existing pattern, not the web route's own `SportsTeamsStore.all` call), and return as an id-keyed object.
- iOS's `SportsTeamDetail` model gains a `teamsById: [String: SportsTeam]` field (mirroring `SportsLeagueDetail`'s existing field of the same name/shape).
- `SportsTeamDetailView` passes `teamsById: detail.teamsById` into both `MatchRow` call sites (Upcoming and Recent Results), mirroring exactly how `SportsLeagueDetailView` already does it.
- **No change** to the web app, to `upcoming_for_team`/`recent_finals_for_team` themselves, or to any other sports route.

## Capabilities

### Modified Capabilities
- `mobile-sports`: the team-detail response gains `teams_by_id` so iOS can resolve opponent names in Upcoming/Recent Results, matching the league-detail response's existing shape.

## Impact

- **Backend**: `app/main.rb`'s `GET /api/v1/sports/teams/:slug` route only (reuses the existing `build_teams_by_id_for_matches` helper — no new helper needed).
- **iOS**: `Sports.swift` (`SportsTeamDetail` model), `SportsTeamDetailView.swift` (pass `teamsById` to both `MatchRow` calls).
- No database/migration changes, no changes to data that's already being synced.
