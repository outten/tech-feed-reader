-- Sports Phase S1 — top-level topic on every feed.
--
-- Existing app shipped as tech-only: every feed in the catalog and
-- in the user's subscriptions is technology-related. Adding sports
-- (NFL / NBA / MLS / Rugby / Tennis) creates a need to filter
-- /articles by top-level topic and (later) scope the For You ranker
-- so a thumbs-up on an Eagles article doesn't influence a tech
-- ranking and vice versa.
--
-- Naming: `topic` (not `category`) because FeedCatalog already
-- uses :category for the sub-grouping (`:aggregator`, `:engineering`,
-- `:podcast`, ...). Two-level taxonomy:
--    feeds.topic        — top level (technology / sports / general)
--    catalog `:category` — sub level inside that topic
--
-- Backfill: every existing row is technology — that's the entire
-- pre-Sports universe. The default for new rows is 'general' so
-- arbitrary URLs added via the /feeds form don't get mis-tagged
-- as sports or tech.
ALTER TABLE feeds ADD COLUMN topic TEXT NOT NULL DEFAULT 'general';
UPDATE feeds SET topic = 'technology';

-- Index on topic so the upcoming /articles?topic=sports filter (a
-- WHERE clause through state_query) doesn't full-scan once the
-- feeds table grows.
CREATE INDEX idx_feeds_topic ON feeds(topic);
