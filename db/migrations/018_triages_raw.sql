-- Persist the raw model output on every triage row.
--
-- Two production runs have come back with status=parse_error and
-- the only diagnostic on the row was the truncated 200-char head of
-- the parser's exception message — not enough to reproduce. With raw
-- saved we can re-run the parser offline against historical bad
-- responses, AND show "View raw output" on parse_error rows so the
-- user can read what Claude actually said.
ALTER TABLE triages ADD COLUMN raw TEXT;
