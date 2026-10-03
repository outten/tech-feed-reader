## Context

`GET /api/v1/sports/leagues/:slug` already solved this exact problem (`app/main.rb:4309-4310`): it collects the home/away team ids referenced by its `upcoming`/`recent_finals` matches and returns a scoped `teams_by_id` lookup via the existing `build_teams_by_id_for_matches` helper (`app/main.rb:992-995`, originally built for the calendar/ICS views to avoid N+1 team lookups). `SportsLeagueDetailView.swift` already consumes this (`MatchRow(match: $0, teamsById: detail.teamsById)`). `GET /api/v1/sports/teams/:slug` (`app/main.rb:4248-4269`) never got the same addition — its `upcoming`/`recent_finals` are raw match rows with only numeric team ids, and `SportsTeamDetailView.swift` calls `MatchRow(match: $0)` with no lookup map, so `MatchRow`'s fallback-to-"TBD" path is what the user is seeing.

## Goals / Non-Goals

**Goals:**
- Team-detail's Upcoming and Recent Results sections show real opponent names, matching the league-detail screen and the web app.

**Non-Goals:**
- No change to how matches are synced/stored, or to the web app (already correct).
- No change to the league-detail route (already correct — it's the reference pattern).

## Decisions

### Reuse `build_teams_by_id_for_matches`, not a bespoke lookup
The team route gets the identical one-line treatment the league route already has:
```ruby
team_ids = (upcoming + recent_finals).flat_map { |m| [m['home_team_id'], m['away_team_id']] }.compact.uniq
teams_by_id = SportsTeamsStore.find_many(team_ids).each_with_object({}) { |t, h| h[t['id']] = t }
```
(Team-detail has no standings-derived ids to fold in, unlike the league route's `team_ids` which also includes `standings.map { |r| r['team_id'] }` — team-detail's own `standings` is a single row for the team itself, already known via `team`, so nothing extra to add there.)

**Alternative considered**: have iOS resolve opponent names by making a second API call per unresolved match. Rejected — the backend already has every team row in hand when building the response; a scoped lookup here is one query, versus N round-trips client-side for no benefit.

## Risks / Trade-offs

None of note — this mirrors an existing, already-shipped pattern in the same file for the sibling route.
