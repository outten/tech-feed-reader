-- Phase A1 (consumer auth, 2026-05-13). One row per registered
-- passkey. Multi-credential per user is supported from day one so
-- the user can add their laptop + phone as separate credentials.
--
-- public_key is the base64url-encoded COSE_Key the WebAuthn server
-- library returns from registration verification. sign_count is the
-- monotonic counter the authenticator increments on each use — we
-- enforce it must increase on every login to detect cloned creds.
-- transports is the comma-separated list ("usb", "nfc", "ble",
-- "internal") the browser tells us — surfaces in UI later.
-- label is optional human-readable name ("iPhone 17", "Work laptop")
-- for the future "manage my passkeys" screen.
CREATE TABLE webauthn_credentials (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id       INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  credential_id TEXT    NOT NULL,
  public_key    TEXT    NOT NULL,
  sign_count    INTEGER NOT NULL DEFAULT 0,
  transports    TEXT,
  label         TEXT,
  created_at    TIMESTAMP NOT NULL DEFAULT (datetime('now')),
  last_used_at  TIMESTAMP
);

CREATE UNIQUE INDEX idx_webauthn_credentials_credential_id
  ON webauthn_credentials(credential_id);
CREATE INDEX idx_webauthn_credentials_user_id
  ON webauthn_credentials(user_id);
