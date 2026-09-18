## Requirements

### Requirement: Stock symbols are searchable
The system SHALL expose `GET /api/v1/stocks/search` accepting a `q` parameter, returning matching symbols, matching the web app's `/stocks` search.

#### Scenario: Search with results
- **WHEN** an authenticated client requests `GET /api/v1/stocks/search?q=apple` and the quote provider is available
- **THEN** the response is HTTP 200 with matching symbols

### Requirement: Quote detail and per-symbol news
The system SHALL expose `GET /api/v1/stocks/:symbol` (quote, refreshing the cache if stale, plus follow state) and `GET /api/v1/stocks/:symbol/news` (recent articles from the symbol's news feed), matching the web app's `/stocks/:symbol` and `/stocks/:symbol/news`.

#### Scenario: Quote detail
- **WHEN** an authenticated client requests `GET /api/v1/stocks/AAPL`
- **THEN** the response is HTTP 200 with the cached (or freshly refreshed) quote and the user's follow state

#### Scenario: Symbol news
- **WHEN** an authenticated client requests `GET /api/v1/stocks/AAPL/news`
- **THEN** the response is HTTP 200 with recent articles from that symbol's news feed

### Requirement: Following a symbol subscribes its news feed
The system SHALL expose `POST`/`DELETE /api/v1/stocks/follow` (body/query `symbol`). Following a symbol SHALL also subscribe the user to that symbol's news feed and eager-fetch both the quote and the feed, matching the web app's follow behavior — not just recording the follow.

#### Scenario: Follow a symbol
- **WHEN** an authenticated user follows a new symbol
- **THEN** the follow is recorded
- **THEN** the user is subscribed to that symbol's news feed

#### Scenario: Unfollow a symbol
- **WHEN** an authenticated user unfollows a previously-followed symbol
- **THEN** the follow is removed and the news feed is unsubscribed (the feed/articles themselves stay, reusable by other followers or a re-follow)

### Requirement: Ticker and index sparklines
The system SHALL expose `GET /api/v1/stocks/ticker` (followed symbols + major world indices, deduped, indices/symbols without a cached quote still included with name-only) and `GET /api/v1/stocks/sparklines` (intraday sparkline data for the major indices), matching the existing `/api/ticker` and `/api/stocks/sparklines` behavior for a token-authenticated client.

#### Scenario: Ticker includes indices even when uncached
- **WHEN** an authenticated user requests `GET /api/v1/stocks/ticker`
- **THEN** all major indices appear in the response, with name-only entries for any not yet cached

### Requirement: iOS app supports stock search, follow, detail, and a ticker
The iOS app SHALL let a signed-in user search for symbols, follow/unfollow them, view quote detail with news, and see a ticker of followed symbols + major indices.

#### Scenario: Follow and view
- **WHEN** a signed-in user searches for a symbol and follows it
- **THEN** it appears in their ticker and its detail page shows quote + news

### Requirement: Symbol detail supports historical price charts
The system SHALL expose `GET /api/v1/stocks/:symbol/history?days=` returning daily-close price points for the requested window (`days` ∈ {7, 30, 60, 90}; any other value falls back to 30), and the iOS app SHALL render this as a line chart on the symbol detail screen with a control to switch between the four ranges. This is new functionality (not a web parity gap — the web app has no historical chart for an individual symbol, only intraday sparklines for the major-index cards).

#### Scenario: Fetch a supported range
- **WHEN** an authenticated client requests `GET /api/v1/stocks/AAPL/history?days=60`
- **THEN** the response includes `days: 60` and an array of `{t, c}` points (timestamp, close price)

#### Scenario: Unsupported range falls back
- **WHEN** an authenticated client requests a `days` value outside `{7, 30, 60, 90}`
- **THEN** the response uses `days: 30`

#### Scenario: iOS shows a range picker and chart
- **WHEN** a signed-in user opens a symbol's detail page
- **THEN** they see a 7D/30D/60D/90D range control and a price chart for the selected range
