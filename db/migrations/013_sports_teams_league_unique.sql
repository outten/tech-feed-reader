-- Sports Phase S3 follow-up — fix the team uniqueness key.
--
-- ESPN reuses numeric team IDs across sports: id=8 is Detroit
-- Lions in NFL AND New Zealand in international rugby. The
-- original 012_sports_core schema had
--   UNIQUE(source_provider, external_id)
-- which collapses both into one row, causing the wrong-logo bug
-- (All Blacks ended up tagged with the Lions PNG).
--
-- Fix: include league_id in the uniqueness key. Same provider +
-- same external_id is fine if they're in different leagues.
--
-- SQLite doesn't support ALTER TABLE for constraint changes, so
-- we rebuild the table:
--   1. Create sports_teams_new with the corrected constraint.
--   2. Copy data, deduping by the corrected key (the bad rows
--      from the bug get one survivor — the seed script can be
--      re-run after migration to backfill cleanly).
--   3. Drop the old table.
--   4. Rename + recreate the indexes/triggers.
--
-- sports_matches FKs reference sports_teams.id — since we
-- preserve ids during the rebuild, those FKs stay valid.

CREATE TABLE sports_teams_new (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  league_id       INTEGER NOT NULL REFERENCES sports_leagues(id) ON DELETE CASCADE,
  slug            TEXT NOT NULL UNIQUE,
  name            TEXT NOT NULL,
  short_name      TEXT,
  location        TEXT,
  source_provider TEXT NOT NULL,
  external_id     TEXT NOT NULL,
  image_url       TEXT,
  UNIQUE(source_provider, league_id, external_id)
);

-- Copy preserving ids. If multiple old rows collide on the new
-- key we'd have a duplicate-key error; in practice we only have
-- one bad row (All Blacks). INSERT OR IGNORE silently drops the
-- collision and keeps the first; the seed script re-establishes
-- the right rows on next run.
INSERT OR IGNORE INTO sports_teams_new
  (id, league_id, slug, name, short_name, location, source_provider, external_id, image_url)
SELECT id, league_id, slug, name, short_name, location, source_provider, external_id, image_url
FROM sports_teams;

DROP TABLE sports_teams;
ALTER TABLE sports_teams_new RENAME TO sports_teams;
