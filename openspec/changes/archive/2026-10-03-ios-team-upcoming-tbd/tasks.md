## 1. Backend

- [x] 1.1 In `GET /api/v1/sports/teams/:slug`'s DB-backed branch, build `teams_by_id` from `upcoming` + `recent_finals` using the existing `build_teams_by_id_for_matches` helper.
- [x] 1.2 Include `teams_by_id` in both the DB-backed and catalog-only-fallback response branches (empty hash for the catalog-only branch, matching the league route's convention).
- [x] 1.3 Request spec: a team with an upcoming match against a known opponent returns that opponent's id in `teams_by_id`.
- [x] 1.4 Run the full RSpec suite.

## 2. iOS

- [x] 2.1 Add `teamsById: [String: SportsTeam]` to `SportsTeamDetail` in `Sports.swift`, matching `SportsLeagueDetail`'s existing field.
- [x] 2.2 Pass `teamsById: detail.teamsById` into both `MatchRow` call sites in `SportsTeamDetailView.swift` (Upcoming and Recent Results sections).
- [x] 2.2b Made `teamsById` optional (`[String: SportsTeam]?`) on both `SportsTeamDetail` and `SportsLeagueDetail`, coalescing to `[:]` at every usage site — a required field broke decoding entirely against production, which didn't have this backend change deployed yet. Verified via decode test against both the old (no `teams_by_id` key) and new response shapes.
- [x] 2.3 Build (Debug + Release) and confirm no compile errors.

## 3. Verification

- [x] 3.1 Restart the dev server (Puma doesn't hot-reload); curl `GET /api/v1/sports/teams/:slug` for a team with real upcoming matches and confirm `teams_by_id` is populated.
- [x] 3.2 Install on the iPad Pro Simulator (Release/production, per standing convention) — user confirmed the decode-error regression (from 2.2b) is fixed; real opponent names depend on the backend being deployed (not yet, as of this check).
- [ ] 3.3 Confirm Recent Results shows real opponent names too (same underlying bug/fix). — blocked on deploy, not separately re-checked after deploy yet.
- [x] 3.4 Pause for explicit manual-verification approval before committing, per the standing UI-change rule. — user confirmed.

## 4. Wrap-up

- [ ] 4.1 `openspec archive` this change once verified.
