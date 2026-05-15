-- STUFF #28 (Phase 28.2) — publisher-supplied category tags.
--
-- FeedParser already gets `entry.categories` from feedjira for both
-- RSS (<category>) and Atom (<category term="...">), plus podcast feeds
-- often expose `<itunes:keywords>` via the same interface. Storing
-- them per-article gives TopicClusters a strong, publisher-curated
-- prior over the noisy keyword-extraction path.
--
-- Stored as JSON-encoded TEXT (an array of lowercased, trimmed,
-- deduped strings). NULL = "we don't know yet" for an article that
-- was imported pre-#28; the import path now UPDATEs the column on
-- duplicate uid as long as it's still NULL, so the next sync-feeds
-- cycle backfills the corpus naturally over the following 24h.
-- Manual immediate backfill: `make refresh-all`.

ALTER TABLE articles ADD COLUMN categories TEXT;
