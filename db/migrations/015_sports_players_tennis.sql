-- Sports Phase S7 — tennis player rankings.
--
-- Extends the existing sports_players table (skeleton from S3)
-- with the fields the ATP/WTA rankings sync populates. Each row
-- represents one ranked player on one tour; (source_provider,
-- external_id) is unique per S3 schema, so a player who appears
-- in both tours (rare — usually a junior crossover) gets two
-- rows — one per tour.
--
-- Why these columns:
--   tour          — 'atp' or 'wta', drives table-grouping on
--                    /sports/tennis
--   current_rank  — 1-based world ranking
--   previous_rank — last week's rank (for trend arrows on the
--                    rankings page)
--   points        — tour-points total (REAL because ESPN
--                    sometimes returns a float like 14350.0)
--   trend         — '↑'/'↓'/'-' or ESPN's bare display string,
--                    stored as TEXT so we don't have to enumerate
--                    every variant
--   headshot_url  — player photo (ESPN CDN)
--   flag_url      — country flag image (ESPN CDN)
--   last_synced_at — set by sync_sports.rb each run
ALTER TABLE sports_players ADD COLUMN tour           TEXT;
ALTER TABLE sports_players ADD COLUMN current_rank   INTEGER;
ALTER TABLE sports_players ADD COLUMN previous_rank  INTEGER;
ALTER TABLE sports_players ADD COLUMN points         REAL;
ALTER TABLE sports_players ADD COLUMN trend          TEXT;
ALTER TABLE sports_players ADD COLUMN headshot_url   TEXT;
ALTER TABLE sports_players ADD COLUMN flag_url       TEXT;
ALTER TABLE sports_players ADD COLUMN last_synced_at TEXT;

-- Index on (tour, current_rank) so the rankings page renders
-- with a single sorted scan per tour.
CREATE INDEX idx_sports_players_tour_rank
  ON sports_players(tour, current_rank);
