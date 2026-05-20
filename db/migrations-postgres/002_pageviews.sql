-- STUFF #48.1 — admin-area pageview analytics. PG dialect.
--
-- Mirror of db/migrations/025_pageviews.sql in the SQLite chain
-- but with PG-idiomatic types (BIGSERIAL id, TIMESTAMP occurred_at)
-- to match the rest of the PG schema from 001_init.sql.
--
-- See the SQLite migration for the design rationale; this file
-- exists so prod (which runs against PG) picks up the same table.
CREATE TABLE pageviews (
  id          BIGSERIAL PRIMARY KEY,
  user_id     BIGINT,
  path        TEXT      NOT NULL,
  section     TEXT,
  status      INTEGER   NOT NULL,
  occurred_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX idx_pageviews_occurred_at         ON pageviews(occurred_at);
CREATE INDEX idx_pageviews_section_occurred_at ON pageviews(section, occurred_at);
CREATE INDEX idx_pageviews_user_id_occurred_at ON pageviews(user_id, occurred_at);
