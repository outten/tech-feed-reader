-- Phase 5 — mute filters. Per-user negative rules that hard-hide
-- matching articles from /articles (and any list view that goes
-- through ArticlesStore.state_query). Distinct from per-feed weights:
-- weights are a soft demotion in the Phase 6 ranker; mutes are an
-- "I never want to see this" hard cut. Articles still live in the
-- DB and are reachable via /search so the user can recover one.
--
-- kind   = 'keyword' | 'author' | 'feed'
-- value  = the literal to match against (substring for keyword,
--          exact for author, feed_id-as-string for feed)
-- (kind, value) is the natural key — re-adding the same rule is a
-- no-op (INSERT OR IGNORE in the store).
CREATE TABLE mute_rules (
  kind       TEXT NOT NULL CHECK(kind IN ('keyword', 'author', 'feed')),
  value      TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (kind, value)
);

-- Lookup index for the NOT EXISTS sub-query that ArticlesStore.state_query
-- uses on every list render. PK already covers (kind, value); a kind-only
-- index speeds the per-row evaluation when most rows match no rule.
CREATE INDEX idx_mute_rules_kind ON mute_rules(kind);
