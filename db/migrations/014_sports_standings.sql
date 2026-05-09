-- Sports Phase S8 — league standings.
--
-- One row per (league, group, team) snapshot. "group" captures
-- the sub-bucket within a league: e.g. "NFC East" / "AFC West"
-- for NFL, "Eastern Conference" / "Western Conference" for
-- NBA + MLS, "Pool 2025" or similar for international rugby.
-- The group_name is whatever the provider returns, normalised to
-- a short string.
--
-- Snapshot semantics: standings change throughout the season, so
-- we want the latest. Idempotent UPSERT on
-- (source_provider, league_id, group_name, team_id) so re-running
-- the sync overwrites the same row instead of appending. last_
-- synced_at lets the UI show "as of X ago" + lets a future
-- optimisation skip already-fresh rows.
--
-- All stats stored as INTEGER / TEXT — the provider's `stats[]`
-- array has 20+ fields per entry; we capture the ones the UI
-- actually shows. New stats can land later as columns without a
-- shape break.
CREATE TABLE sports_standings (
  id                 INTEGER PRIMARY KEY AUTOINCREMENT,
  league_id          INTEGER NOT NULL REFERENCES sports_leagues(id) ON DELETE CASCADE,
  team_id            INTEGER NOT NULL REFERENCES sports_teams(id)   ON DELETE CASCADE,
  group_name         TEXT NOT NULL,                  -- "NFC East", "Eastern Conference", etc.
  position           INTEGER,                        -- 1-based rank within the group
  wins               INTEGER,
  losses             INTEGER,
  ties               INTEGER,
  win_percent        TEXT,                           -- ESPN ships ".647" — stored as text to preserve formatting
  points_for         INTEGER,                        -- runs / goals / points scored
  points_against     INTEGER,
  point_differential INTEGER,
  games_behind       TEXT,                           -- "-" or "2.5" — ESPN ships display string
  streak             TEXT,                           -- "L1", "W3"
  playoff_seed       INTEGER,
  source_provider    TEXT NOT NULL,
  last_synced_at     TEXT,
  UNIQUE(source_provider, league_id, group_name, team_id)
);

CREATE INDEX idx_sports_standings_league ON sports_standings(league_id);
CREATE INDEX idx_sports_standings_group  ON sports_standings(league_id, group_name, position);
