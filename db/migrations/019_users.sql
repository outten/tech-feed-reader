-- Phase A1 (consumer auth, 2026-05-13). Users table — username is the
-- canonical identity, no email anywhere. display_name is optional UI
-- nicety; falls back to username in the layout chip. last_seen_at is
-- bumped on every authenticated request so admin pages can show
-- "active in last 24h" later.
CREATE TABLE users (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  username      TEXT    NOT NULL,
  display_name  TEXT,
  created_at    TIMESTAMP NOT NULL DEFAULT (datetime('now')),
  last_seen_at  TIMESTAMP
);

-- Usernames are case-insensitive in practice; we store them
-- lowercased and enforce uniqueness via a plain UNIQUE index. (No
-- COLLATE NOCASE because we normalize at the write boundary in
-- UsersStore.create — keeps SQL portable + the index small.)
CREATE UNIQUE INDEX idx_users_username ON users(username);
