-- STUFF #48.1 — admin-area pageview analytics.
--
-- Every dynamic request gets one row via RequestLogMiddleware. The
-- middleware sits ahead of the Sinatra app, so we see every path
-- (including static-asset hits) — the middleware itself filters
-- out the noise paths (/health, /metrics, css/js/img) before the
-- insert so the table only carries user-meaningful pageviews.
--
-- section is the derived bucket (articles / podcasts / youtube /
-- sports / feeds / admin / auth / NULL for "other") so the admin
-- analytics page can render per-section aggregates without
-- re-deriving on every query.
--
-- Retention: opportunistic 90-day prune fires on /admin/analytics
-- visits (see app/main.rb). Cheap query, no recurring-job
-- dependency.
CREATE TABLE pageviews (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id     INTEGER,                       -- NULL when anonymous
  path        TEXT    NOT NULL,
  section     TEXT,
  status      INTEGER NOT NULL,
  occurred_at TEXT    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Daily-aggregate scans hit occurred_at; per-section breakdowns
-- want (section, occurred_at); per-user surfaces (not yet built
-- but cheap to anticipate) hit (user_id, occurred_at).
CREATE INDEX idx_pageviews_occurred_at         ON pageviews(occurred_at);
CREATE INDEX idx_pageviews_section_occurred_at ON pageviews(section, occurred_at);
CREATE INDEX idx_pageviews_user_id_occurred_at ON pageviews(user_id, occurred_at);
