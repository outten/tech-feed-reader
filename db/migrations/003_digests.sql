-- Stored digests. Each row is a snapshot of a digest run produced by
-- scripts/generate_digest.rb (typically fired daily from cron). The
-- /digests UI lists rows newest-first; /digests/:id renders the
-- stored html_body inline.
--
-- We keep both text_body and html_body so the same record could be
-- emailed in the future (re-render would change subtly; storing both
-- locks in what was generated). article_count + window_hours give
-- the listing UI enough metadata to summarise without re-parsing the
-- body.

CREATE TABLE digests (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  generated_at  TEXT    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  window_hours  INTEGER NOT NULL,
  article_count INTEGER NOT NULL,
  subject       TEXT    NOT NULL,
  text_body     TEXT    NOT NULL,
  html_body     TEXT    NOT NULL
);

CREATE INDEX idx_digests_generated_at ON digests(generated_at DESC);
