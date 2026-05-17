-- Phase 5 / D-PG-2. Consolidated PostgreSQL schema for tech-feed-reader.
--
-- This single migration produces the same final schema state that
-- migrations 001-024 produce on SQLite. We don't replay the SQLite
-- history per migration because Postgres is starting empty and we
-- want a clean dialect-correct schema (no table-rebuild dance from
-- 013 / 022, no FTS5 virtual tables, no datetime('now')).
--
-- Whenever a new column / table lands on main, write the corresponding
-- 0NN_*.sql migration in BOTH directories — db/migrations/ for the
-- SQLite path (incremental) AND db/migrations-postgres/ (also
-- incremental from this baseline 001_init).
--
-- Schema_migrations is created by the migration runner (app/database.rb)
-- before this file ever executes — don't redeclare it.
--
-- Key dialect differences vs the SQLite chain:
--   * INTEGER PRIMARY KEY AUTOINCREMENT → BIGSERIAL PRIMARY KEY
--     (BIGSERIAL chosen over INTEGER to dodge future overflow; the
--     app casts ids to Integer at the Ruby boundary anyway).
--   * Timestamps stay TEXT (ISO8601 strings) — the application code
--     reads/writes them as strings and bypasses any timezone-aware
--     PG semantics. Date filters cast via ::date in stores.
--   * FTS5 articles_fts virtual table replaced by a generated
--     tsvector column on articles + a GIN index. PG-side
--     to_tsvector / plainto_tsquery / ts_headline replace the
--     SQLite MATCH / snippet() calls in ArticlesStore.search +
--     .for_topic + Recommendation.for_article. Branch on
--     Database.adapter at those call sites.
--   * CHECK(kind IN (...)) syntax is identical in both dialects.
--
-- Tables are declared in dependency order so FK targets exist at
-- CREATE time. Groups:
--   1. users + auth
--   2. feeds + subscriptions
--   3. articles + their per-article state
--   4. AI surfaces (digests, triages)
--   5. sports
--   6. misc (background_pool, llm_usage)

-- ---------------------------------------------------------------------
-- 1. Users + auth (migrations 019, 020, 021)
-- ---------------------------------------------------------------------

CREATE TABLE users (
  id            BIGSERIAL PRIMARY KEY,
  username      TEXT      NOT NULL,
  display_name  TEXT,
  created_at    TIMESTAMP NOT NULL DEFAULT now(),
  last_seen_at  TIMESTAMP
);
CREATE UNIQUE INDEX idx_users_username ON users(username);

CREATE TABLE webauthn_credentials (
  id            BIGSERIAL PRIMARY KEY,
  user_id       BIGINT    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  credential_id TEXT      NOT NULL,
  public_key    TEXT      NOT NULL,
  sign_count    INTEGER   NOT NULL DEFAULT 0,
  transports    TEXT,
  label         TEXT,
  created_at    TIMESTAMP NOT NULL DEFAULT now(),
  last_used_at  TIMESTAMP
);
CREATE UNIQUE INDEX idx_webauthn_credentials_credential_id ON webauthn_credentials(credential_id);
CREATE INDEX        idx_webauthn_credentials_user_id      ON webauthn_credentials(user_id);

CREATE TABLE recovery_codes (
  id           BIGSERIAL PRIMARY KEY,
  user_id      BIGINT    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code_hash    TEXT      NOT NULL,
  created_at   TIMESTAMP NOT NULL DEFAULT now(),
  consumed_at  TIMESTAMP
);
CREATE UNIQUE INDEX idx_recovery_codes_code_hash ON recovery_codes(code_hash);
CREATE INDEX        idx_recovery_codes_user_id  ON recovery_codes(user_id);

-- ---------------------------------------------------------------------
-- 2. Feeds + per-user subscriptions (migrations 001, 005, 011, 022)
-- ---------------------------------------------------------------------

CREATE TABLE feeds (
  id                     BIGSERIAL PRIMARY KEY,
  url                    TEXT    NOT NULL UNIQUE,
  title                  TEXT,
  fetch_interval_seconds INTEGER NOT NULL DEFAULT 3600,
  last_fetched_at        TEXT,
  last_etag              TEXT,
  last_modified          TEXT,
  last_status            TEXT,
  created_at             TEXT    NOT NULL DEFAULT (now()::text),
  image_url              TEXT,
  topic                  TEXT    NOT NULL DEFAULT 'general'
);
CREATE INDEX idx_feeds_last_fetched_at ON feeds(last_fetched_at);
CREATE INDEX idx_feeds_topic           ON feeds(topic);

CREATE TABLE user_feed_subscriptions (
  id         BIGSERIAL PRIMARY KEY,
  user_id    BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  feed_id    BIGINT NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL DEFAULT (now()::text),
  UNIQUE (user_id, feed_id)
);
CREATE INDEX idx_ufs_feed_id ON user_feed_subscriptions(feed_id);

CREATE TABLE feed_feedback (
  user_id    BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  feed_id    BIGINT NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
  weight     DOUBLE PRECISION NOT NULL DEFAULT 1.0,
  updated_at TEXT NOT NULL DEFAULT (now()::text),
  PRIMARY KEY (user_id, feed_id)
);
CREATE INDEX idx_feed_feedback_feed_id ON feed_feedback(feed_id);

-- ---------------------------------------------------------------------
-- 3. Articles + per-article state (migrations 001, 002, 005, 006, 007,
-- 008, 022, 023)
-- ---------------------------------------------------------------------

CREATE TABLE articles (
  id                     BIGSERIAL PRIMARY KEY,
  uid                    TEXT    NOT NULL UNIQUE,
  feed_id                BIGINT  NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
  title                  TEXT    NOT NULL,
  url                    TEXT    NOT NULL,
  author                 TEXT,
  published_at           TEXT,
  content_html           TEXT,
  content_text           TEXT,
  fetched_at             TEXT    NOT NULL DEFAULT (now()::text),
  audio_url              TEXT,
  audio_mime_type        TEXT,
  audio_duration_seconds INTEGER,
  image_url              TEXT,
  categories             TEXT,
  -- FTS5 replacement: generated tsvector + GIN index. Stored (not
  -- VIRTUAL) so the index is usable without re-computing per query.
  tsv                    tsvector GENERATED ALWAYS AS (
    to_tsvector('english',
                coalesce(title, '') || ' ' || coalesce(content_text, ''))
  ) STORED
);
CREATE INDEX idx_articles_feed_id      ON articles(feed_id);
CREATE INDEX idx_articles_published_at ON articles(published_at DESC);
CREATE INDEX idx_articles_tsv          ON articles USING GIN (tsv);

CREATE TABLE read_state (
  user_id          BIGINT NOT NULL REFERENCES users(id)    ON DELETE CASCADE,
  article_id       BIGINT NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
  read             INTEGER NOT NULL DEFAULT 0,
  bookmarked       INTEGER NOT NULL DEFAULT 0,
  archived         INTEGER NOT NULL DEFAULT 0,
  opened_at        TEXT,
  feedback         INTEGER NOT NULL DEFAULT 0,
  passive_feedback INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, article_id)
);
CREATE INDEX idx_read_state_article_id ON read_state(article_id);

CREATE TABLE tags (
  id          BIGSERIAL PRIMARY KEY,
  user_id     BIGINT  NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name        TEXT    NOT NULL,
  match_kind  TEXT    NOT NULL CHECK (match_kind IN ('regex', 'keyword', 'feed_id')),
  match_value TEXT    NOT NULL,
  created_at  TEXT    NOT NULL DEFAULT (now()::text),
  UNIQUE (user_id, name)
);
CREATE INDEX idx_tags_user_id ON tags(user_id);

CREATE TABLE article_tags (
  article_id BIGINT NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
  tag_id     BIGINT NOT NULL REFERENCES tags(id)     ON DELETE CASCADE,
  PRIMARY KEY (article_id, tag_id)
);
CREATE INDEX idx_article_tags_tag_id ON article_tags(tag_id);

CREATE TABLE summaries (
  article_id   BIGINT PRIMARY KEY REFERENCES articles(id) ON DELETE CASCADE,
  extractive   TEXT,
  llm          TEXT,
  llm_model    TEXT,
  generated_at TEXT NOT NULL DEFAULT (now()::text)
);

CREATE TABLE mute_rules (
  user_id    BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind       TEXT NOT NULL CHECK(kind IN ('keyword', 'author', 'feed')),
  value      TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (now()::text),
  PRIMARY KEY (user_id, kind, value)
);
CREATE INDEX idx_mute_rules_user_id_kind ON mute_rules(user_id, kind);

-- ---------------------------------------------------------------------
-- 4. AI surfaces — digests + triages (migrations 003, 009, 010, 017, 018, 022)
-- ---------------------------------------------------------------------

CREATE TABLE digests (
  id                BIGSERIAL PRIMARY KEY,
  user_id           BIGINT  NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  generated_at      TEXT    NOT NULL DEFAULT (now()::text),
  window_hours      INTEGER NOT NULL,
  article_count     INTEGER NOT NULL,
  subject           TEXT    NOT NULL,
  text_body         TEXT    NOT NULL,
  html_body         TEXT    NOT NULL,
  llm_summary       TEXT,
  llm_model         TEXT,
  llm_generated_at  TEXT
);
CREATE INDEX idx_digests_user_id_generated_at ON digests(user_id, generated_at DESC);

CREATE TABLE triages (
  id            BIGSERIAL PRIMARY KEY,
  user_id       BIGINT  NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  generated_at  TEXT    NOT NULL DEFAULT (now()::text),
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
CREATE INDEX idx_triages_user_id_generated_at ON triages(user_id, generated_at DESC);

-- ---------------------------------------------------------------------
-- 5. Sports (migrations 012, 013, 014, 015, 016, 022)
-- ---------------------------------------------------------------------

CREATE TABLE sports_leagues (
  id              BIGSERIAL PRIMARY KEY,
  slug            TEXT NOT NULL UNIQUE,
  name            TEXT NOT NULL,
  sport           TEXT NOT NULL,
  source_provider TEXT NOT NULL,
  external_id     TEXT NOT NULL,
  country         TEXT,
  season_year     INTEGER,
  UNIQUE(source_provider, external_id)
);

CREATE TABLE sports_teams (
  id                  BIGSERIAL PRIMARY KEY,
  league_id           BIGINT NOT NULL REFERENCES sports_leagues(id) ON DELETE CASCADE,
  slug                TEXT NOT NULL UNIQUE,
  name                TEXT NOT NULL,
  short_name          TEXT,
  location            TEXT,
  source_provider     TEXT NOT NULL,
  external_id         TEXT NOT NULL,
  image_url           TEXT,
  articles_indexed_at TIMESTAMP,
  UNIQUE(source_provider, league_id, external_id)
);

CREATE TABLE sports_matches (
  id              BIGSERIAL PRIMARY KEY,
  league_id       BIGINT NOT NULL REFERENCES sports_leagues(id) ON DELETE CASCADE,
  home_team_id    BIGINT REFERENCES sports_teams(id) ON DELETE SET NULL,
  away_team_id    BIGINT REFERENCES sports_teams(id) ON DELETE SET NULL,
  scheduled_at    TEXT NOT NULL,
  status          TEXT NOT NULL DEFAULT 'scheduled',
  home_score      INTEGER,
  away_score      INTEGER,
  period          TEXT,
  venue           TEXT,
  source_provider TEXT NOT NULL,
  external_id     TEXT NOT NULL,
  last_synced_at  TEXT,
  UNIQUE(source_provider, external_id)
);
CREATE INDEX idx_sports_matches_scheduled ON sports_matches(scheduled_at);
CREATE INDEX idx_sports_matches_status    ON sports_matches(status);
CREATE INDEX idx_sports_matches_home      ON sports_matches(home_team_id);
CREATE INDEX idx_sports_matches_away      ON sports_matches(away_team_id);

CREATE TABLE sports_players (
  id                  BIGSERIAL PRIMARY KEY,
  sport               TEXT NOT NULL,
  slug                TEXT NOT NULL UNIQUE,
  full_name           TEXT NOT NULL,
  country             TEXT,
  image_url           TEXT,
  source_provider     TEXT NOT NULL,
  external_id         TEXT NOT NULL,
  tour                TEXT,
  current_rank        INTEGER,
  previous_rank       INTEGER,
  points              DOUBLE PRECISION,
  trend               TEXT,
  headshot_url        TEXT,
  flag_url            TEXT,
  last_synced_at      TEXT,
  articles_indexed_at TIMESTAMP,
  UNIQUE(source_provider, external_id)
);
CREATE INDEX idx_sports_players_tour_rank ON sports_players(tour, current_rank);

CREATE TABLE sports_follows (
  id         BIGSERIAL PRIMARY KEY,
  user_id    BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind       TEXT NOT NULL CHECK(kind IN ('team', 'player', 'league')),
  value      TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (now()::text),
  UNIQUE (user_id, kind, value)
);
CREATE INDEX idx_sports_follows_user_id_kind ON sports_follows(user_id, kind);

CREATE TABLE sports_standings (
  id                 BIGSERIAL PRIMARY KEY,
  league_id          BIGINT NOT NULL REFERENCES sports_leagues(id) ON DELETE CASCADE,
  team_id            BIGINT NOT NULL REFERENCES sports_teams(id)   ON DELETE CASCADE,
  group_name         TEXT NOT NULL,
  position           INTEGER,
  wins               INTEGER,
  losses             INTEGER,
  ties               INTEGER,
  win_percent        TEXT,
  points_for         INTEGER,
  points_against     INTEGER,
  point_differential INTEGER,
  games_behind       TEXT,
  streak             TEXT,
  playoff_seed       INTEGER,
  source_provider    TEXT NOT NULL,
  last_synced_at     TEXT,
  UNIQUE(source_provider, league_id, group_name, team_id)
);
CREATE INDEX idx_sports_standings_league ON sports_standings(league_id);
CREATE INDEX idx_sports_standings_group  ON sports_standings(league_id, group_name, position);

CREATE TABLE sports_entity_articles (
  kind       TEXT      NOT NULL,
  entity_id  BIGINT    NOT NULL,
  article_id BIGINT    NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
  matched_at TIMESTAMP NOT NULL DEFAULT now(),
  PRIMARY KEY (kind, entity_id, article_id)
);
CREATE INDEX idx_sports_entity_articles_lookup
  ON sports_entity_articles(kind, entity_id, matched_at DESC);

-- ---------------------------------------------------------------------
-- 6. Misc — background_pool, llm_usage (migrations 004, 024)
-- ---------------------------------------------------------------------

CREATE TABLE background_pool (
  picsum_id    INTEGER PRIMARY KEY,
  author       TEXT,
  unsplash_url TEXT,
  added_at     TEXT NOT NULL DEFAULT (now()::text)
);

CREATE TABLE llm_usage (
  id            BIGSERIAL PRIMARY KEY,
  user_id       BIGINT  NOT NULL,
  route         TEXT    NOT NULL,
  model         TEXT,
  input_tokens  INTEGER NOT NULL DEFAULT 0,
  output_tokens INTEGER NOT NULL DEFAULT 0,
  cost_usd      DOUBLE PRECISION NOT NULL DEFAULT 0,
  created_at    TEXT    NOT NULL DEFAULT (now()::text)
);
CREATE INDEX idx_llm_usage_user_created ON llm_usage(user_id, created_at);
CREATE INDEX idx_llm_usage_created      ON llm_usage(created_at);
