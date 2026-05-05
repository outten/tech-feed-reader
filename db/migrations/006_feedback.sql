-- Phase 3 — feedback signal foundation. Two pieces:
--
-- 1. read_state.feedback: per-article 👍/👎 valence as an integer.
--    0 = no signal (default; treated identically to "today" in every
--    read path until Phase 6 lands the ranker), +1 = thumbs up,
--    -1 = thumbs down. Toggling 👍 a second time writes 0 (clear).
--
-- 2. feed_feedback: per-feed weight as a REAL multiplier. Default 1.0;
--    "show more" bumps +0.25, "show less" bumps -0.25, clamped to
--    0.25..3.0 by the FeedFeedbackStore module. ON DELETE CASCADE
--    so removing a feed cleans up its weight row.
--
-- No backfill needed — both surfaces are additive (no existing
-- read_state rows referenced feedback; no feed_feedback rows existed
-- at all). Read paths are unchanged: feedback is only consumed by the
-- Phase 6 ranker, which doesn't ship in this migration.
ALTER TABLE read_state ADD COLUMN feedback INTEGER NOT NULL DEFAULT 0;

CREATE TABLE feed_feedback (
  feed_id    INTEGER PRIMARY KEY REFERENCES feeds(id) ON DELETE CASCADE,
  weight     REAL    NOT NULL DEFAULT 1.0,
  updated_at TEXT    NOT NULL DEFAULT CURRENT_TIMESTAMP
);
