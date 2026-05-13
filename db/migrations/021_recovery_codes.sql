-- Phase A1 (consumer auth, 2026-05-13). One-time recovery codes —
-- the escape hatch when a user has lost all their passkeys AND
-- platform sync (iCloud / Google / Bitwarden). 10 codes minted at
-- signup, shown ONCE on the post-signup screen.
--
-- We store HMAC-SHA256(code, SESSION_SECRET) — not bcrypt, because
-- codes are high-entropy + single-use, so the slow-hashing cost
-- isn't justified and would make recovery slow when a user pastes
-- their code. consumed_at flips on first successful use; we never
-- delete rows so the user can see in a future "my recovery codes"
-- screen which ones they've burned.
CREATE TABLE recovery_codes (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id      INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code_hash    TEXT    NOT NULL,
  created_at   TIMESTAMP NOT NULL DEFAULT (datetime('now')),
  consumed_at  TIMESTAMP
);

CREATE UNIQUE INDEX idx_recovery_codes_code_hash ON recovery_codes(code_hash);
CREATE INDEX idx_recovery_codes_user_id ON recovery_codes(user_id);
