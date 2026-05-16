-- Phase deploy-prep — per-call LLM usage log for cost containment.
--
-- Every successful Anthropic API call on a user-facing route writes
-- a row here. LlmGuard reads it to enforce per-user daily token
-- quotas and a global hourly circuit-breaker before allowing a new
-- call, so a buggy client or hostile signup can't drain the API key.
--
-- Why a separate log table (not extending triages / digests / summaries):
-- chat has no persistent record at all, and the four routes each store
-- their results in different shapes. A flat usage table normalised by
-- (user_id, route, created_at) lets the guard answer "how many tokens
-- has user N spent in the last 24h" with one query regardless of
-- which routes they used.
CREATE TABLE llm_usage (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id       INTEGER NOT NULL,
  route         TEXT    NOT NULL,            -- '/triage', '/chat', etc.
  model         TEXT,
  input_tokens  INTEGER NOT NULL DEFAULT 0,
  output_tokens INTEGER NOT NULL DEFAULT 0,
  cost_usd      REAL    NOT NULL DEFAULT 0,  -- API-equivalent, via DevStats.cost_for
  created_at    TEXT    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- (user_id, created_at) covers the per-user 24h window query;
-- created_at alone covers the global hourly circuit-breaker query.
CREATE INDEX idx_llm_usage_user_created ON llm_usage(user_id, created_at);
CREATE INDEX idx_llm_usage_created      ON llm_usage(created_at);
