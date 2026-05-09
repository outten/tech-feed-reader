-- Sports Phase S7 follow-up #2 — articles-mentioning-entity cache.
--
-- Followed players + teams need an "Articles mentioning <name>"
-- surface on their detail pages. FTS5 phrase search is fast, but
-- we still cache hits per-entity so:
--   1. The detail page renders from a single indexed read instead
--      of running a MATCH on every visit.
--   2. We can mark the entity with a freshness timestamp and skip
--      re-running FTS5 within a TTL (default 1h).
--
-- Polymorphic on (kind, entity_id) — kind is 'player' (sports_players.id)
-- or 'team' (sports_teams.id). ON DELETE CASCADE on article_id only;
-- entity rows live in different tables, refresh handles their lifecycle.
CREATE TABLE sports_entity_articles (
  kind       TEXT    NOT NULL,
  entity_id  INTEGER NOT NULL,
  article_id INTEGER NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
  matched_at TIMESTAMP NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (kind, entity_id, article_id)
);

CREATE INDEX idx_sports_entity_articles_lookup
  ON sports_entity_articles(kind, entity_id, matched_at DESC);

-- Per-entity freshness timestamps so refresh-if-stale is a single
-- column read instead of a MAX() over the join table.
ALTER TABLE sports_players ADD COLUMN articles_indexed_at TIMESTAMP;
ALTER TABLE sports_teams   ADD COLUMN articles_indexed_at TIMESTAMP;
