## ADDED Requirements

### Requirement: Home endpoint bundles today's dashboard data
The system SHALL expose `GET /api/v1/home` returning: `stats` (unread/bookmarks/total-article counts), `today_matches` (the caller's followed teams'/leagues' matches scheduled today, each with `home_team`/`away_team` merged in), `live_matches` (all currently-live matches, same team merge), and `today_reading`/`today_listening`/`today_watching` (articles published today, partitioned by plain/podcast/YouTube — same partitioning the web `/` dashboard uses, each capped at 10).

#### Scenario: Stats reflect the caller's account
- **WHEN** an authenticated user with 3 unread and 1 bookmarked article requests `GET /api/v1/home`
- **THEN** `stats.unread` is 3 and `stats.bookmarks` is 1

#### Scenario: Today's articles are partitioned by kind
- **WHEN** an authenticated user has a plain article, a podcast episode, and a YouTube video all published today
- **THEN** each appears in exactly one of `today_reading`/`today_listening`/`today_watching`, matching its kind

#### Scenario: Matches include team info
- **WHEN** an authenticated user has a followed team with a match scheduled today
- **THEN** the match in `today_matches` includes nested `home_team`/`away_team` objects, not just team ids

#### Scenario: Nothing today
- **WHEN** an authenticated user has no matches, no live matches, and no articles published today
- **THEN** the response is HTTP 200 with empty arrays for every list (not an error)

### Requirement: iOS has a Home screen that is the sidebar's default landing item
The iOS app SHALL show a Home screen (stats row, live matches, today's matches, to-read/to-listen/to-watch sections, and a "Continue Listening" section built from locally-stored podcast resume positions) as the sidebar's default selection, so opening the app no longer lands on an empty "Select an Item" placeholder.

#### Scenario: App opens to Home
- **WHEN** a signed-in user opens the app with no prior selection
- **THEN** the Home screen is shown, not "Select an Item"

#### Scenario: Continue Listening reflects local resume positions
- **WHEN** a user has partially played a podcast episode (a resume position is stored locally, per Phase 13)
- **THEN** that episode appears in the Home screen's "Continue Listening" section

#### Scenario: Empty state
- **WHEN** the `GET /api/v1/home` response has every list empty and no resume positions are stored locally
- **THEN** the Home screen shows a "Nothing new today" empty state instead of a blank screen
