-- Migration 001 — initial schema for tech-feed-reader v1.
--
-- Single SQLite DB at data/app.db replaces the file-per-store pattern that
-- t-money-terminal uses; FTS5 backs /search. WAL mode and PRAGMA
-- foreign_keys=ON are set in app/database.rb on connection open, not
-- here, so this file stays pure schema.
--
-- schema_migrations is created by the migration runner before this file
-- ever executes — don't redeclare it.
--
-- Identity model:
--   articles.id       INTEGER PK (rowid; FTS5 content_rowid links to it)
--   articles.uid      TEXT UNIQUE — SHA1(feed_url + article_url)[0,12];
--                                    used in URLs (/article/abc123def456)
--
-- Foreign keys cascade on delete: removing a feed nukes its articles,
-- which nukes their read_state, summaries, and article_tags rows.

CREATE TABLE feeds (
  id                     INTEGER PRIMARY KEY AUTOINCREMENT,
  url                    TEXT    NOT NULL UNIQUE,
  title                  TEXT,
  fetch_interval_seconds INTEGER NOT NULL DEFAULT 3600,
  last_fetched_at        TEXT,
  last_etag              TEXT,
  last_modified          TEXT,
  last_status            TEXT,
  created_at             TEXT    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_feeds_last_fetched_at ON feeds(last_fetched_at);

CREATE TABLE articles (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  uid          TEXT    NOT NULL UNIQUE,
  feed_id      INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
  title        TEXT    NOT NULL,
  url          TEXT    NOT NULL,
  author       TEXT,
  published_at TEXT,
  content_html TEXT,
  content_text TEXT,
  fetched_at   TEXT    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_articles_feed_id      ON articles(feed_id);
CREATE INDEX idx_articles_published_at ON articles(published_at DESC);

CREATE TABLE read_state (
  article_id INTEGER PRIMARY KEY REFERENCES articles(id) ON DELETE CASCADE,
  read       INTEGER NOT NULL DEFAULT 0,
  bookmarked INTEGER NOT NULL DEFAULT 0,
  archived   INTEGER NOT NULL DEFAULT 0,
  opened_at  TEXT
);

CREATE TABLE tags (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  name        TEXT    NOT NULL UNIQUE,
  match_kind  TEXT    NOT NULL CHECK (match_kind IN ('regex', 'keyword', 'feed_id')),
  match_value TEXT    NOT NULL,
  created_at  TEXT    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE article_tags (
  article_id INTEGER NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
  tag_id     INTEGER NOT NULL REFERENCES tags(id)     ON DELETE CASCADE,
  PRIMARY KEY (article_id, tag_id)
);

CREATE INDEX idx_article_tags_tag_id ON article_tags(tag_id);

CREATE TABLE summaries (
  article_id   INTEGER PRIMARY KEY REFERENCES articles(id) ON DELETE CASCADE,
  extractive   TEXT,
  llm          TEXT,
  llm_model    TEXT,
  generated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- FTS5 over articles(title, content_text) using external-content mode:
-- the index references articles.id (the rowid) instead of duplicating
-- text. Triggers below keep the index in sync on every write.
CREATE VIRTUAL TABLE articles_fts USING fts5(
  title,
  content_text,
  content='articles',
  content_rowid='id'
);

CREATE TRIGGER articles_fts_ai AFTER INSERT ON articles BEGIN
  INSERT INTO articles_fts(rowid, title, content_text)
  VALUES (new.id, new.title, new.content_text);
END;

CREATE TRIGGER articles_fts_ad AFTER DELETE ON articles BEGIN
  INSERT INTO articles_fts(articles_fts, rowid, title, content_text)
  VALUES ('delete', old.id, old.title, old.content_text);
END;

CREATE TRIGGER articles_fts_au AFTER UPDATE ON articles BEGIN
  INSERT INTO articles_fts(articles_fts, rowid, title, content_text)
  VALUES ('delete', old.id, old.title, old.content_text);
  INSERT INTO articles_fts(rowid, title, content_text)
  VALUES (new.id, new.title, new.content_text);
END;
