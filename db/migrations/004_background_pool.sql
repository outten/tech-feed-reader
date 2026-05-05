-- Pool of Picsum image IDs that page-background.js rotates through.
-- Empty table = the JS falls back to its bundled default (a small
-- curated set of nature photos). When the user clicks "Refresh
-- pool" in /admin/backgrounds, BackgroundPool.refresh! wipes this
-- table and writes a fresh batch fetched from Picsum's /v2/list.
--
-- author + unsplash_url are persisted so the admin page can render
-- thumbnails + "by … on Unsplash" without having to re-fetch
-- /id/<id>/info per row.
CREATE TABLE background_pool (
  picsum_id    INTEGER PRIMARY KEY,
  author       TEXT,
  unsplash_url TEXT,
  added_at     TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
