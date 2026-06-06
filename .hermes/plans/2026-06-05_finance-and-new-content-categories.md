# Finance / Markets + New Content Categories — Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Add four new content topics (Finance/Markets, World News, Science, Gaming) with ~30 curated RSS feeds, plus a stock symbol search/follow/ticker feature modelled on the existing sports-follows pattern.

**Architecture:** RSS feeds are catalog-only additions — no new infrastructure. The stock feature adds a `stock_follows` table (mirroring `sports_follows`), a `StockQuoteProvider` backed by Finnhub (free tier, 60 req/min), a stock info page at `/stocks/:symbol`, and a ticker bar displaying followed symbols. Stock data syncs on follow + periodic background refresh via Sidekiq.

**Tech Stack:** Finnhub API (free, API key required), existing Sinatra/PG/Sidekiq stack, follows pattern from sports.

---

## Phase 1: New Content Categories (RSS-only — no new code patterns)

### Task 1.1: Add topics + categories to FeedCatalog

**Objective:** Register four new topics and their sub-categories.

**Files:**
- Modify: `app/feed_catalog.rb` — TOPICS, CATEGORIES, CATEGORY_TO_TOPIC

**Changes to TOPICS:**
```ruby
TOPICS = {
  technology: 'Technology',
  sports:     'Sports',
  nature:     'Nature & Documentary',
  humor:      'Humor',
  finance:    'Finance & Markets',       # NEW
  world_news: 'World News',             # NEW
  science:    'Science',                 # NEW
  gaming:     'Gaming'                  # NEW
}.freeze
```

**New CATEGORIES entries (append before `.freeze`):**
```ruby
# Finance & Markets
markets_news:  'Market news',

# World News
world:         'World news',

# Science
science_pub:   'Science publishers',
space:         'Space & astronomy',

# Gaming
gaming_pub:    'Gaming publishers',
```

**New CATEGORY_TO_TOPIC entries:**
```ruby
markets_news:  :finance,
world:         :world_news,
science_pub:   :science,
space:         :science,
gaming_pub:    :gaming,
```

### Task 1.2: Add curated RSS feeds to CATALOG

**Objective:** Add ~30 verified RSS feeds across the four new topics.

**File:** `app/feed_catalog.rb` — append to CATALOG array.

**Finance & Markets (6 feeds):**
```ruby
# ---- Finance & Markets ------------------------------------------------
{ url: 'https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=100003114',
  title: 'CNBC Top News', category: :markets_news },
{ url: 'https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=15839069',
  title: 'CNBC Investing', category: :markets_news },
{ url: 'https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=20910258',
  title: 'CNBC Economy', category: :markets_news },
{ url: 'https://feeds.content.dowjones.io/public/rss/mw_topstories',
  title: 'MarketWatch Top Stories', category: :markets_news },
{ url: 'https://seekingalpha.com/feed.xml',
  title: 'Seeking Alpha', category: :markets_news },
{ url: 'https://news.google.com/rss/topics/CAAqJggKIiBDQkFTRWdvSUwyMHZNRGx6TVdZU0FtVnVHZ0pWVXlnQVAB',
  title: 'Google News — Business', category: :markets_news },
```

**World News (8 feeds):**
```ruby
# ---- World News -------------------------------------------------------
{ url: 'https://www.aljazeera.com/xml/rss/all.xml',
  title: 'Al Jazeera', category: :world },
{ url: 'https://feeds.npr.org/1001/rss.xml',
  title: 'NPR News', category: :world },
{ url: 'https://rss.nytimes.com/services/xml/rss/nyt/World.xml',
  title: 'NYT World News', category: :world },
{ url: 'https://feeds.washingtonpost.com/rss/world',
  title: 'Washington Post — World', category: :world },
{ url: 'https://feeds.theguardian.com/theguardian/world/rss',
  title: 'The Guardian — World', category: :world },
{ url: 'https://www.cbsnews.com/latest/rss/world',
  title: 'CBS News — World', category: :world },
{ url: 'https://news.un.org/feed/subscribe/en/news/all/rss.xml',
  title: 'UN News', category: :world },
{ url: 'https://www.france24.com/en/rss',
  title: 'France 24', category: :world },
```

**Science (8 feeds):**
```ruby
# ---- Science ----------------------------------------------------------
{ url: 'https://www.nature.com/nature.rss',
  title: 'Nature', category: :science_pub },
{ url: 'https://www.newscientist.com/section/news/feed/',
  title: 'New Scientist', category: :science_pub },
{ url: 'https://www.sciencedaily.com/rss/all.xml',
  title: 'ScienceDaily', category: :science_pub },
{ url: 'https://feeds.arstechnica.com/arstechnica/science',
  title: 'Ars Technica — Science', category: :science_pub },
{ url: 'https://www.quantamagazine.org/feed/',
  title: 'Quanta Magazine', category: :science_pub },
{ url: 'https://www.nasa.gov/news-release/feed/',
  title: 'NASA News', category: :space },
{ url: 'https://www.space.com/feeds/all',
  title: 'Space.com', category: :space },
{ url: 'https://www.livescience.com/feeds/all',
  title: 'Live Science', category: :science_pub },
```

**Gaming (8 feeds):**
```ruby
# ---- Gaming -----------------------------------------------------------
{ url: 'https://kotaku.com/rss',
  title: 'Kotaku', category: :gaming_pub },
{ url: 'https://feeds.feedburner.com/ign/all',
  title: 'IGN', category: :gaming_pub },
{ url: 'https://www.pcgamer.com/rss/',
  title: 'PC Gamer', category: :gaming_pub },
{ url: 'https://www.rockpapershotgun.com/feed',
  title: 'Rock Paper Shotgun', category: :gaming_pub },
{ url: 'https://www.eurogamer.net/feed',
  title: 'Eurogamer', category: :gaming_pub },
{ url: 'https://www.polygon.com/rss/index.xml',
  title: 'Polygon', category: :gaming_pub },
{ url: 'https://www.gamespot.com/feeds/mashup/',
  title: 'GameSpot', category: :gaming_pub },
{ url: 'https://www.destructoid.com/feed/',
  title: 'Destructoid', category: :gaming_pub },
```

### Task 1.3: Add onboarding starters + chips for new topics

**Objective:** So new users see the new topics on /welcome.

**File:** `app/feed_catalog.rb` — ONBOARDING_STARTERS, ONBOARDING_CHIPS

**ONBOARDING_STARTERS additions:**
```ruby
finance: %w[
  https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=100003114
  https://feeds.content.dowjones.io/public/rss/mw_topstories
  https://seekingalpha.com/feed.xml
].freeze,
world_news: %w[
  https://www.aljazeera.com/xml/rss/all.xml
  https://feeds.npr.org/1001/rss.xml
  https://rss.nytimes.com/services/xml/rss/nyt/World.xml
].freeze,
science: %w[
  https://www.nature.com/nature.rss
  https://www.nasa.gov/news-release/feed/
  https://www.quantamagazine.org/feed/
].freeze,
gaming: %w[
  https://kotaku.com/rss
  https://www.pcgamer.com/rss/
  https://www.polygon.com/rss/index.xml
].freeze,
```

**ONBOARDING_CHIPS additions:**
```ruby
finance:    { label: 'Finance',    blurb: 'CNBC, MarketWatch, Seeking Alpha — market headlines.', emoji: '📈' },
world_news: { label: 'World News', blurb: 'NPR, NYT, Al Jazeera, The Guardian — global coverage.', emoji: '🌍' },
science:    { label: 'Science',    blurb: 'Nature, NASA, Quanta Magazine — research & discovery.', emoji: '🔬' },
gaming:     { label: 'Gaming',     blurb: 'Kotaku, IGN, PC Gamer, Polygon — game news & reviews.', emoji: '🎮' },
```

---

## Phase 2: Stock Symbols — Database & Store

### Task 2.1: Migration — stock_follows + stock_quotes tables

**Objective:** Create the DB schema for stock follows and cached quote data.

**File:** `db/migrations-postgres/NNN_stock_follows.sql` (next migration number)

```sql
-- Stock follows: which symbols each user tracks.
-- Mirrors sports_follows but specialised for equities.
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
CREATE TABLE IF NOT EXISTS stock_quotes (
  symbol          TEXT PRIMARY KEY,        -- uppercase ticker
  name            TEXT,                    -- company name
  exchange        TEXT,                    -- NASDAQ, NYSE, etc.
  sector          TEXT,
  industry        TEXT,
  market_cap      BIGINT,
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
```

### Task 2.2: StockFollowsStore module

**Objective:** CRUD for stock follows, mirroring SportsFollowsStore.

**File:** `app/stock_follows_store.rb`

Key methods:
- `all(user_id)` → all followed symbols for a user
- `follow?(user_id, symbol)` → boolean
- `add(user_id:, symbol:, name: nil)` → idempotent INSERT ON CONFLICT DO NOTHING
- `remove(user_id:, symbol:)` → DELETE
- `count(user_id)` → integer
- `distinct_symbols` → all unique symbols across all users (drives sync)

### Task 2.3: StockQuotesStore module

**Objective:** Read/write cached quote data.

**File:** `app/stock_quotes_store.rb`

Key methods:
- `find(symbol)` → single quote row or nil
- `find_many(symbols)` → array of quote rows (for ticker bar)
- `upsert(symbol:, data_hash)` → INSERT ON CONFLICT UPDATE
- `stale?(symbol, max_age_seconds: 300)` → true if updated_at older than threshold

---

## Phase 3: Stock Quote Provider (Finnhub API)

### Task 3.1: StockQuoteProvider module

**Objective:** Thin wrapper around Finnhub's REST API.

**File:** `app/stock_quote_provider.rb`

**Environment:** `FINNHUB_API_KEY` in `.credentials`.

**Methods:**
- `search(query)` → symbol search (GET /search?q=...) → [{symbol, description, type}]
- `quote(symbol)` → current price (GET /quote?symbol=...) → {c, d, dp, h, l, o, pc, t}
- `profile(symbol)` → company info (GET /stock/profile2?symbol=...) → {name, exchange, sector, industry, marketCapitalization, logo, ...}
- `fetch_and_cache(symbol)` → calls quote() + profile(), merges, upserts into StockQuotesStore

**Rate limiting:** Finnhub free tier = 60 req/min. The provider should enforce a simple sleep-based throttle (or token bucket) so batch refreshes don't blow the limit.

**Error handling:** 429 → retry after 1s. 403/401 → log + skip (bad key). Network errors → log + skip.

---

## Phase 4: Routes & Views

### Task 4.1: Stock search page — GET /stocks

**Objective:** Page with a search box. User types a company name or ticker, gets results, can click through to a stock detail page.

**File:** `app/main.rb` (route), `views/stocks.erb`

**Route:** `GET /stocks` — renders the search page. If `?q=...` param present, calls `StockQuoteProvider.search(q)` and renders results inline.

**View:** Search bar at top + results list below showing symbol, company name, exchange. Each result links to `/stocks/:symbol`.

### Task 4.2: Stock detail page — GET /stocks/:symbol

**Objective:** Show company info + current quote for a single symbol. Follow/unfollow button.

**File:** `app/main.rb` (route), `views/stock_detail.erb`

**Route:** `GET /stocks/:symbol` — calls `StockQuotesStore.find(symbol)`. If stale or missing, triggers `StockQuoteProvider.fetch_and_cache(symbol)`. Renders detail page.

**View layout:**
- Header: company name, symbol, exchange
- Price section: current price, change ($), change (%), coloured green/red
- Details: open, day high/low, prev close, volume, market cap, sector/industry
- Follow button (same pattern as sports: form with class `js-stock-follow-form`)

### Task 4.3: Follow/unfollow routes

**Objective:** POST endpoints for following/unfollowing a stock symbol.

**File:** `app/main.rb`

**Routes:**
- `POST /stocks/follow` — params: symbol, name. Calls `StockFollowsStore.add`, enqueues `StockQuoteFetchWorker` for immediate data. Returns JSON or redirect.
- `POST /stocks/unfollow` — params: symbol. Calls `StockFollowsStore.remove`. Returns JSON or redirect.

Same dual JSON/HTML response pattern as sports follow routes.

### Task 4.4: Stock ticker bar (partial)

**Objective:** A horizontal scrolling ticker that shows all followed symbols with price + change. Appears on the dashboard or as a global bar.

**File:** `views/_stock_ticker.erb`, `public/stock-ticker.css`, `public/stock-ticker.js`

**Rendering:** Server-side partial included in layout (or dashboard). Fetches `StockFollowsStore.all(user_id)` → symbols → `StockQuotesStore.find_many(symbols)`. Renders a horizontally scrolling bar with:
```
AAPL $207.34 ▲+1.25 (+0.61%)  |  MSFT $442.10 ▼-3.20 (-0.72%)  |  ...
```

Green for positive change, red for negative. CSS animation for smooth scrolling.

**Empty state:** If user follows no stocks, ticker is hidden (no empty bar).

### Task 4.5: Client-side follow JS

**Objective:** AJAX follow/unfollow without page reload, same pattern as sports-follow.js.

**File:** `public/stock-follow.js`

Intercepts `form.js-stock-follow-form` submit → POST via fetch with JSON accept → toggles button state (+ Follow / ✓ Following). Same `applyState()` pattern as `public/sports-follow.js`.

---

## Phase 5: Background Sync

### Task 5.1: StockQuoteFetchWorker (Sidekiq)

**Objective:** Background job to refresh quote data for a single symbol.

**File:** `app/workers/stock_quote_fetch_worker.rb`

```ruby
class StockQuoteFetchWorker
  include Sidekiq::Worker
  sidekiq_options queue: :default, retry: 2

  def perform(symbol)
    StockQuoteProvider.fetch_and_cache(symbol.upcase)
  end
end
```

### Task 5.2: StockSyncWorker (periodic bulk refresh)

**Objective:** Refresh all followed symbols. Runs on a schedule (e.g. every 15 min during market hours, hourly otherwise).

**File:** `app/workers/stock_sync_worker.rb`

```ruby
class StockSyncWorker
  include Sidekiq::Worker

  def perform
    symbols = StockFollowsStore.distinct_symbols
    symbols.each_with_index do |sym, i|
      # Throttle: Finnhub free = 60/min → ~1 req/sec is safe
      sleep(1.1) if i > 0
      StockQuoteProvider.fetch_and_cache(sym)
    end
  end
end
```

Wire into the scheduler or cron.

---

## Phase 6: Navigation & Integration

### Task 6.1: Add /stocks to navigation

**Objective:** Add a nav link so users can find the stocks page.

**Files:** `views/layout.erb` or nav partial, wherever the main nav links live.

Add "Stocks 📈" link pointing to `/stocks`.

### Task 6.2: Wire ticker into dashboard/layout

**Objective:** Render the stock ticker bar for logged-in users who follow at least one symbol.

**File:** `views/layout.erb` or `views/dashboard.erb` — include `_stock_ticker.erb` partial when `@stock_quotes` is present and non-empty.

The route helper should set `@stock_quotes` only when the user has follows, so the partial is conditionally rendered.

---

## Phase 7: Tests

### Task 7.1: StockFollowsStore spec

**File:** `spec/stock_follows_store_spec.rb`

Test: add, remove, follow?, all, count, distinct_symbols, idempotent add, cascade on user delete.

### Task 7.2: StockQuotesStore spec

**File:** `spec/stock_quotes_store_spec.rb`

Test: upsert, find, find_many, stale?.

### Task 7.3: StockQuoteProvider spec

**File:** `spec/stock_quote_provider_spec.rb`

Test: search, quote, profile — stub Net::HTTP responses. Test error handling (429, network failure).

### Task 7.4: Stock routes spec

**File:** `spec/stocks_spec.rb`

Test: GET /stocks (search page), GET /stocks/:symbol (detail), POST /stocks/follow, POST /stocks/unfollow. Both JSON and HTML response paths.

### Task 7.5: Feed catalog spec updates

**File:** `spec/feed_catalog_spec.rb`

Ensure existing tests pass with new topics/categories. Add tests for new topic keys in TOPICS, CATEGORIES, CATEGORY_TO_TOPIC consistency.

---

## Phase 8: Documentation

### Task 8.1: Update docs

**Files:**
- `README.md` — add Stocks page + new content topics to page table
- `AGENTS.md` — add StockQuoteProvider, stock_follows, stock_quotes to tables/architecture
- `STUFF.md` — add item #85 (or next number) tracking this feature

---

## Implementation Order

1. **Phase 1** (catalog feeds) — pure data, zero risk, immediately useful
2. **Phase 2** (DB + stores) — foundation for stock feature
3. **Phase 3** (Finnhub provider) — API integration
4. **Phase 4** (routes + views) — user-facing stock pages + ticker
5. **Phase 5** (background sync) — keep data fresh
6. **Phase 6** (nav integration) — wire it all together
7. **Phase 7** (tests) — though TDD means writing tests alongside each phase
8. **Phase 8** (docs) — in the same PR

All phases land in one branch: `outten/TODO-XXX` (number TBD — next available).

---

## Risks & Open Questions

1. **Finnhub free tier limits (60 req/min):** With 30 followed symbols, a full sync takes ~30s. Acceptable for a personal/team app. If the team grows, consider caching more aggressively or upgrading.

2. **Market hours awareness:** Should the sync run more frequently during NYSE/NASDAQ hours (9:30am–4pm ET)? Or just a flat 15-min interval? Start flat, optimize later.

3. **Ticker placement:** Global bar in layout (always visible) vs. dashboard-only? Suggest dashboard + /stocks page initially; promote to global later if users want it.

4. **Finnhub API key:** Needs to be added to `.credentials` as `FINNHUB_API_KEY`. Free signup at https://finnhub.io/. The app should degrade gracefully (hide stock features) if the key is missing, same as Claude API key.

5. **Non-US symbols:** Finnhub free tier covers US equities well. For FTSE (London) symbols, the format is different (e.g. `VOD.L`). Worth testing but may need special handling.

6. **Do we want index-level data?** (^DJI, ^GSPC, ^IXIC, ^FTSE) — Finnhub may not support index symbols on free tier. Could use a dedicated market-summary endpoint or just link to news feeds for that.
