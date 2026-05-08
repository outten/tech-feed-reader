-- Phase 8 — persisted triage runs. Mirrors the digests-table pattern:
-- one row per run, must_read / optional / skip stored as JSON arrays
-- so the model + UI can evolve without a migration.
--
-- Why JSON columns: the structured output from Triage::Claude is
-- already a hash of arrays of {uid, rationale}. Round-tripping
-- through JSON keeps the storage layer agnostic about future
-- additions (e.g. a Confidence score per entry).
CREATE TABLE triages (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  generated_at  TEXT    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  unread_count  INTEGER NOT NULL,
  model         TEXT,
  must_read     TEXT    NOT NULL DEFAULT '[]',  -- JSON: [{uid, rationale}, ...]
  optional      TEXT    NOT NULL DEFAULT '[]',
  skip          TEXT    NOT NULL DEFAULT '[]',
  status        TEXT    NOT NULL,               -- :ok | :parse_error | :empty | :unavailable | :error
  error         TEXT,
  latency_ms    INTEGER,
  input_tokens  INTEGER,
  output_tokens INTEGER
);

CREATE INDEX idx_triages_generated_at ON triages(generated_at DESC);
