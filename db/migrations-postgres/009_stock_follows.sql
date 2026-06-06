-- STUFF #85: Stock symbol follows + cached quote data.
-- Mirrors the sports_follows pattern: users follow symbols, a sync
-- job refreshes cached quotes, the dashboard renders a ticker bar.

CREATE TABLE IF NOT EXISTS stock_follows (
  id         BIGSERIAL PRIMARY KEY,
  user_id    BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  symbol     TEXT NOT NULL,               -- uppercase ticker, e.g. 'AAPL'
  name       TEXT,                        -- company name at follow time
  created_at TEXT NOT NULL DEFAULT (now()::text),
  UNIQUE (user_id, symbol)
);
CREATE INDEX IF NOT EXISTS idx_stock_follows_user ON stock_follows(user_id);

-- Cached quote snapshots. One row per symbol, updated by the sync job.
-- The ticker bar and /stocks/:symbol detail page read from here —
-- never from the Finnhub API on page render (cache-only contract).
CREATE TABLE IF NOT EXISTS stock_quotes (
  symbol          TEXT PRIMARY KEY,        -- uppercase ticker
  name            TEXT,                    -- company name
  exchange        TEXT,                    -- NASDAQ, NYSE, etc.
  sector          TEXT,
  industry        TEXT,
  market_cap      BIGINT,
  logo            TEXT,                    -- company logo URL from Finnhub
  price           NUMERIC(12,4),
  change          NUMERIC(12,4),          -- absolute $ change
  change_pct      NUMERIC(8,4),           -- % change
  day_high        NUMERIC(12,4),
  day_low         NUMERIC(12,4),
  open            NUMERIC(12,4),
  prev_close      NUMERIC(12,4),
  volume          BIGINT,
  updated_at      TEXT NOT NULL DEFAULT (now()::text)
);
