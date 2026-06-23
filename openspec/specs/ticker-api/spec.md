## ADDED Requirements

### Requirement: Ticker JSON endpoint returns all symbols for signed-in user
The system SHALL expose `GET /api/ticker` that returns a JSON array of quote objects for the signed-in user's ticker. The array SHALL include all followed symbols first, then all major indices, deduped. Every symbol SHALL appear in the response — symbols without a cached quote row SHALL appear with `symbol` and `name` only (no `price`/`change`/`change_pct`). The endpoint SHALL return HTTP 401 for unauthenticated requests.

#### Scenario: User with follows and warm cache
- **WHEN** a signed-in user with followed symbols requests `GET /api/ticker`
- **THEN** the response is HTTP 200 with `Content-Type: application/json`
- **THEN** the JSON array contains the user's followed symbols first, then major indices
- **THEN** each cached symbol includes `symbol`, `name`, `price`, `change`, `change_pct`

#### Scenario: User with follows and cold cache
- **WHEN** a signed-in user requests `GET /api/ticker` and some symbols have no cached quote row
- **THEN** uncached symbols appear in the array with `symbol` and `name` only (`price` is absent or null)
- **THEN** the array still contains ALL expected symbols — none are omitted

#### Scenario: All 10 major indices always present
- **WHEN** a signed-in user requests `GET /api/ticker`
- **THEN** all 10 MAJOR_INDICES symbols (SPY, DIA, QQQ, IWM, EWU, EWG, EWJ, EWH, EWQ, FEZ) appear in the response
- **THEN** index symbols without cached quotes include their display name from `StockQuoteProvider::MAJOR_INDICES`

#### Scenario: Unauthenticated request
- **WHEN** an unauthenticated user requests `GET /api/ticker`
- **THEN** the response is HTTP 401

### Requirement: ticker_quotes helper includes index placeholders
The `ticker_quotes` Sinatra helper SHALL include all major index symbols in its return value even when their quote rows are absent from `stock_quotes`. It SHALL use the `:name` from `StockQuoteProvider::MAJOR_INDICES` as the placeholder name.

#### Scenario: Index not yet cached
- **WHEN** `ticker_quotes` is called and a major index symbol has no row in `stock_quotes`
- **THEN** the symbol appears in the return value as `{ 'symbol' => ..., 'name' => ... }` with no price
- **THEN** the symbol is NOT silently dropped
