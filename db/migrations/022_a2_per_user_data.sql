-- Phase A2 — per-user data split.
--
-- Every table holding user-state gains a NOT NULL user_id FK; the
-- existing single-user dataset is migrated wholesale to user_id = 1
-- (t-money). Done as table-rewrites because:
--   * SQLite ALTER TABLE ADD COLUMN with REFERENCES requires
--     DEFAULT NULL when FKs are on — which would let new INSERTs
--     forget user_id and silently land as NULL.
--   * Three of the tables need their PRIMARY KEY or UNIQUE
--     constraint widened to include user_id (read_state,
--     mute_rules, feed_feedback, tags.name, sports_follows).
--
-- feeds remains a shared catalog. The new user_feed_subscriptions
-- bridge gives each user their own subscription list while a single
-- fetch keeps every subscriber up to date.

-- ---------------------------------------------------------------
-- 0. Seed t-money as user_id = 1.
-- ---------------------------------------------------------------
INSERT OR IGNORE INTO users (id, username, display_name)
VALUES (1, 't-money', 't-money');

-- ---------------------------------------------------------------
-- 1. read_state — composite PK (user_id, article_id).
-- ---------------------------------------------------------------
CREATE TABLE read_state_new (
  user_id          INTEGER NOT NULL REFERENCES users(id)    ON DELETE CASCADE,
  article_id       INTEGER NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
  read             INTEGER NOT NULL DEFAULT 0,
  bookmarked       INTEGER NOT NULL DEFAULT 0,
  archived         INTEGER NOT NULL DEFAULT 0,
  opened_at        TEXT,
  feedback         INTEGER NOT NULL DEFAULT 0,
  passive_feedback INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, article_id)
);
INSERT INTO read_state_new
  (user_id, article_id, read, bookmarked, archived, opened_at, feedback, passive_feedback)
SELECT 1, article_id, read, bookmarked, archived, opened_at, feedback, passive_feedback
  FROM read_state;
DROP TABLE read_state;
ALTER TABLE read_state_new RENAME TO read_state;
CREATE INDEX idx_read_state_article_id ON read_state(article_id);

-- ---------------------------------------------------------------
-- 2. feed_feedback — composite PK (user_id, feed_id).
-- ---------------------------------------------------------------
CREATE TABLE feed_feedback_new (
  user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  feed_id    INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
  weight     REAL    NOT NULL DEFAULT 1.0,
  updated_at TEXT    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, feed_id)
);
INSERT INTO feed_feedback_new (user_id, feed_id, weight, updated_at)
SELECT 1, feed_id, weight, updated_at FROM feed_feedback;
DROP TABLE feed_feedback;
ALTER TABLE feed_feedback_new RENAME TO feed_feedback;
CREATE INDEX idx_feed_feedback_feed_id ON feed_feedback(feed_id);

-- ---------------------------------------------------------------
-- 3. mute_rules — composite PK (user_id, kind, value).
-- ---------------------------------------------------------------
CREATE TABLE mute_rules_new (
  user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind       TEXT NOT NULL CHECK(kind IN ('keyword', 'author', 'feed')),
  value      TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, kind, value)
);
INSERT INTO mute_rules_new (user_id, kind, value, created_at)
SELECT 1, kind, value, created_at FROM mute_rules;
DROP TABLE mute_rules;
ALTER TABLE mute_rules_new RENAME TO mute_rules;
CREATE INDEX idx_mute_rules_user_id_kind ON mute_rules(user_id, kind);

-- ---------------------------------------------------------------
-- 4. tags — name unique per-user (was globally unique).
--    article_tags carries FK tag_id REFERENCES tags(id) ON DELETE
--    CASCADE, so a naive DROP TABLE tags wipes the bridge. Snapshot
--    + restore: tag ids are preserved, so the restored rows still
--    reference valid tags.
-- ---------------------------------------------------------------
CREATE TEMP TABLE article_tags_backup AS SELECT * FROM article_tags;

CREATE TABLE tags_new (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name        TEXT    NOT NULL,
  match_kind  TEXT    NOT NULL CHECK (match_kind IN ('regex', 'keyword', 'feed_id')),
  match_value TEXT    NOT NULL,
  created_at  TEXT    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (user_id, name)
);
INSERT INTO tags_new (id, user_id, name, match_kind, match_value, created_at)
SELECT id, 1, name, match_kind, match_value, created_at FROM tags;
DROP TABLE tags;
ALTER TABLE tags_new RENAME TO tags;
CREATE INDEX idx_tags_user_id ON tags(user_id);

INSERT INTO article_tags (article_id, tag_id)
SELECT article_id, tag_id FROM article_tags_backup;
DROP TABLE article_tags_backup;

-- ---------------------------------------------------------------
-- 5. sports_follows — UNIQUE(user_id, kind, value).
-- ---------------------------------------------------------------
CREATE TABLE sports_follows_new (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind       TEXT NOT NULL CHECK(kind IN ('team', 'player', 'league')),
  value      TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (user_id, kind, value)
);
INSERT INTO sports_follows_new (id, user_id, kind, value, created_at)
SELECT id, 1, kind, value, created_at FROM sports_follows;
DROP TABLE sports_follows;
ALTER TABLE sports_follows_new RENAME TO sports_follows;
CREATE INDEX idx_sports_follows_user_id_kind ON sports_follows(user_id, kind);

-- ---------------------------------------------------------------
-- 6. triages + digests — surrogate-PK tables, simple add-and-copy.
-- ---------------------------------------------------------------
CREATE TABLE triages_new (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id       INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  generated_at  TEXT    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  unread_count  INTEGER NOT NULL,
  model         TEXT,
  must_read     TEXT    NOT NULL DEFAULT '[]',
  optional      TEXT    NOT NULL DEFAULT '[]',
  skip          TEXT    NOT NULL DEFAULT '[]',
  status        TEXT    NOT NULL,
  error         TEXT,
  latency_ms    INTEGER,
  input_tokens  INTEGER,
  output_tokens INTEGER,
  topic         TEXT,
  raw           TEXT
);
INSERT INTO triages_new
  (id, user_id, generated_at, unread_count, model, must_read, optional, skip,
   status, error, latency_ms, input_tokens, output_tokens, topic, raw)
SELECT id, 1, generated_at, unread_count, model, must_read, optional, skip,
       status, error, latency_ms, input_tokens, output_tokens, topic, raw
  FROM triages;
DROP TABLE triages;
ALTER TABLE triages_new RENAME TO triages;
CREATE INDEX idx_triages_user_id_generated_at ON triages(user_id, generated_at DESC);

CREATE TABLE digests_new (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id           INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  generated_at      TEXT    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  window_hours      INTEGER NOT NULL,
  article_count     INTEGER NOT NULL,
  subject           TEXT    NOT NULL,
  text_body         TEXT    NOT NULL,
  html_body         TEXT    NOT NULL,
  llm_summary       TEXT,
  llm_model         TEXT,
  llm_generated_at  TEXT
);
INSERT INTO digests_new
  (id, user_id, generated_at, window_hours, article_count, subject,
   text_body, html_body, llm_summary, llm_model, llm_generated_at)
SELECT id, 1, generated_at, window_hours, article_count, subject,
       text_body, html_body, llm_summary, llm_model, llm_generated_at
  FROM digests;
DROP TABLE digests;
ALTER TABLE digests_new RENAME TO digests;
CREATE INDEX idx_digests_user_id_generated_at ON digests(user_id, generated_at DESC);

-- ---------------------------------------------------------------
-- 7. user_feed_subscriptions — bridge so feeds itself stays shared.
--    Backfill: subscribe user 1 to every existing feed.
-- ---------------------------------------------------------------
CREATE TABLE user_feed_subscriptions (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  feed_id    INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
  created_at TEXT    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (user_id, feed_id)
);
CREATE INDEX idx_ufs_feed_id ON user_feed_subscriptions(feed_id);

INSERT INTO user_feed_subscriptions (user_id, feed_id)
SELECT 1, id FROM feeds;
