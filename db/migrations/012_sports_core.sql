-- Sports Phase S3 — structured-data foundation.
--
-- Five tables sit alongside the existing article schema. They're
-- the prerequisite for live scores, recent results, upcoming
-- fixtures, and standings (Phase S6 second half + S8 + S9). Until
-- those UI surfaces ship in a follow-up PR, this layer is invisible
-- to the user — but `make sync-sports` populates it from ESPN's
-- public endpoints once a day.
--
-- Naming + conventions:
--   - Every external row is keyed by (source_provider, external_id)
--     for idempotent upserts. Re-running sync never duplicates.
--   - league_id / team_id are the local rowids; cascade deletes
--     keep dependent rows clean if a league/team is removed.
--   - `status` on matches uses ESPN's vocabulary:
--       scheduled · live · final · postponed · cancelled
--     The provider normalizes to this set.
--   - `last_synced_at` on matches lets the sync script skip rows
--     that haven't moved (final scores don't change).

CREATE TABLE sports_leagues (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  slug            TEXT NOT NULL UNIQUE,             -- 'nfl', 'nba', 'mls', 'intl-rugby'
  name            TEXT NOT NULL,                    -- 'NFL', 'NBA', 'Major League Soccer', 'International Rugby'
  sport           TEXT NOT NULL,                    -- 'football', 'basketball', 'soccer', 'rugby', 'tennis'
  source_provider TEXT NOT NULL,                    -- 'espn', 'thesportsdb' (future)
  external_id     TEXT NOT NULL,                    -- ESPN sport/league path: 'football/nfl', 'rugby/164205'
  country         TEXT,
  season_year     INTEGER,
  UNIQUE(source_provider, external_id)
);

CREATE TABLE sports_teams (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  league_id       INTEGER NOT NULL REFERENCES sports_leagues(id) ON DELETE CASCADE,
  slug            TEXT NOT NULL UNIQUE,             -- 'eagles', 'sixers', 'union', 'all-blacks'
  name            TEXT NOT NULL,
  short_name      TEXT,
  location        TEXT,
  source_provider TEXT NOT NULL,
  external_id     TEXT NOT NULL,                    -- ESPN team id, e.g. '21' for Eagles
  image_url       TEXT,                             -- logo URL when provider exposes one
  UNIQUE(source_provider, external_id)
);

CREATE TABLE sports_matches (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  league_id       INTEGER NOT NULL REFERENCES sports_leagues(id) ON DELETE CASCADE,
  home_team_id    INTEGER REFERENCES sports_teams(id) ON DELETE SET NULL,
  away_team_id    INTEGER REFERENCES sports_teams(id) ON DELETE SET NULL,
  scheduled_at    TEXT NOT NULL,                    -- ISO8601 UTC
  status          TEXT NOT NULL DEFAULT 'scheduled', -- scheduled|live|final|postponed|cancelled
  home_score      INTEGER,
  away_score      INTEGER,
  period          TEXT,                             -- "Q3", "FT", "HT", null when not in-progress
  venue           TEXT,
  source_provider TEXT NOT NULL,
  external_id     TEXT NOT NULL,
  last_synced_at  TEXT,
  UNIQUE(source_provider, external_id)
);

CREATE INDEX idx_sports_matches_scheduled ON sports_matches(scheduled_at);
CREATE INDEX idx_sports_matches_status    ON sports_matches(status);
CREATE INDEX idx_sports_matches_home      ON sports_matches(home_team_id);
CREATE INDEX idx_sports_matches_away      ON sports_matches(away_team_id);

CREATE TABLE sports_players (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  sport           TEXT NOT NULL,                    -- 'tennis'
  slug            TEXT NOT NULL UNIQUE,
  full_name       TEXT NOT NULL,
  country         TEXT,
  image_url       TEXT,
  source_provider TEXT NOT NULL,
  external_id     TEXT NOT NULL,
  UNIQUE(source_provider, external_id)
);

-- Follows = the user's "I follow these" list. Drives the sync
-- (which entities get pulled per cron run) and the UI (which
-- entities show on /sports overview + per-team pages).
--
-- kind  ∈ team | player | league
-- value = the slug of the followed entity (sports_teams.slug,
--                                          sports_players.slug,
--                                          sports_leagues.slug)
-- Composite UNIQUE(kind, value) so re-following is a no-op.
CREATE TABLE sports_follows (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  kind        TEXT NOT NULL CHECK(kind IN ('team', 'player', 'league')),
  value       TEXT NOT NULL,
  created_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(kind, value)
);

CREATE INDEX idx_sports_follows_kind ON sports_follows(kind);
