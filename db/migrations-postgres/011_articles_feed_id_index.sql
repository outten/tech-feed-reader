-- idx_articles_feed_id was declared in 001_init.sql but never applied to
-- databases created before that line was added. CONCURRENTLY is not allowed
-- inside a transaction, so we use a plain index build (momentary lock).
CREATE INDEX IF NOT EXISTS idx_articles_feed_id ON articles(feed_id);
