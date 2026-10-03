## 1. Backend

- [ ] 1.1 In `GET /api/v1/sports/teams/:slug`'s DB-backed branch, build `teams_by_id` from `upcoming` + `recent_finals` using the existing `build_teams_by_id_for_matches` helper.
- [ ] 1.2 Include `teams_by_id` in both the DB-backed and catalog-only-fallback response branches (empty hash for the catalog-only branch, matching the league route's convention).
- [ ] 1.3 Request spec: a team with an upcoming match against a known opponent returns that opponent's id in `teams_by_id`.
- [ ] 1.4 Run the full RSpec suite.

## 2. iOS

- [ ] 2.1 Add `teamsById: [String: SportsTeam]` to `SportsTeamDetail` in `Sports.swift`, matching `SportsLeagueDetail`'s existing field.
- [ ] 2.2 Pass `teamsById: detail.teamsById` into both `MatchRow` call sites in `SportsTeamDetailView.swift` (Upcoming and Recent Results sections).
- [ ] 2.3 Build (Debug + Release) and confirm no compile errors.

## 3. Verification

- [ ] 3.1 Restart the dev server (Puma doesn't hot-reload); curl `GET /api/v1/sports/teams/:slug` for a team with real upcoming matches and confirm `teams_by_id` is populated.
- [ ] 3.2 Install on the iPad Pro Simulator (Release/production, per standing convention) and confirm a team's Upcoming section shows real opponent names instead of "TBD @ TBD".
- [ ] 3.3 Confirm Recent Results shows real opponent names too (same underlying bug/fix).
- [ ] 3.4 Pause for explicit manual-verification approval before committing, per the standing UI-change rule.

## 4. Wrap-up

- [ ] 4.1 `openspec archive` this change once verified.
