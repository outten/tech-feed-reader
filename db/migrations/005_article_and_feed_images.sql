-- Article-level + feed-level image URLs. Feeds (especially podcasts)
-- ship channel-level cover art via <itunes:image> or <image>; entries
-- often include a thumbnail via <itunes:image> at episode level,
-- <media:thumbnail>, or feedjira's parsed `entry.image`. We persist
-- the URL only — actual image data stays on the publisher's CDN, so
-- pruning an article doesn't need to clean up any extra files.
--
-- All-NULL on existing rows; the next FeedFetcher cycle backfills
-- them as it parses.
ALTER TABLE articles ADD COLUMN image_url TEXT;
ALTER TABLE feeds    ADD COLUMN image_url TEXT;
