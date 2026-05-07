-- Cached Claude summary of a digest. Manual one-shot trigger from
-- /digests/:id; stored permanently per digest row so re-visiting the
-- page never re-spends tokens. Mirrors the summaries.llm column on
-- per-article LLM summaries.
--
-- All three columns are NULL by default — no backfill needed and the
-- /digests/:id view branches on (llm_summary IS NULL) to decide
-- whether to show the "Summarize with Claude" button or the cached
-- text.
ALTER TABLE digests ADD COLUMN llm_summary       TEXT;
ALTER TABLE digests ADD COLUMN llm_model         TEXT;
ALTER TABLE digests ADD COLUMN llm_generated_at  TEXT;
