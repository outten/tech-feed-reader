-- STUFF #73 — Wikipedia summary cache on the league row.
--
-- `wikipedia_title` is the catalog-time slug (e.g. "Tour de France",
-- "2026 Roland Garros") — populated when SportsCatalog declares it
-- and used by Providers::Wikipedia to fetch the REST-API summary.
--
-- `wikipedia_summary` + `wikipedia_summary_fetched_at` cache the
-- response so /sports/league/:slug doesn't hit Wikipedia on every
-- page load. TTL enforced in app code (24h).

ALTER TABLE sports_leagues
  ADD COLUMN IF NOT EXISTS wikipedia_title              TEXT,
  ADD COLUMN IF NOT EXISTS wikipedia_summary            TEXT,
  ADD COLUMN IF NOT EXISTS wikipedia_summary_fetched_at TIMESTAMPTZ;
