-- ios-app change: bearer tokens for native clients (iOS app). Issued
-- alongside the existing WebAuthn ceremonies for browser-less clients
-- that can't hold a cookie session. Only the HMAC hash is stored —
-- mirrors recovery_codes' code_hash approach (see app/recovery_codes_store.rb).

CREATE TABLE IF NOT EXISTS api_tokens (
  id            BIGSERIAL PRIMARY KEY,
  user_id       BIGINT    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash    TEXT      NOT NULL,
  created_at    TIMESTAMP NOT NULL DEFAULT now(),
  last_used_at  TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_api_tokens_token_hash ON api_tokens(token_hash);
CREATE INDEX        IF NOT EXISTS idx_api_tokens_user_id   ON api_tokens(user_id);
