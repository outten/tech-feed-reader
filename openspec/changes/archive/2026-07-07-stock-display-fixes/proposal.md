## Why

Four stock display issues have accumulated since the AJAX ticker shipped: some followed stocks go missing from the ticker, the 5-minute polling refresh adds complexity without meaningful benefit, the ticker scrolls too slowly to see all symbols in a reasonable time, and market cap figures for foreign stocks (e.g., TSM) display in local currency (TWD) rather than USD, producing absurdly large numbers.

## What Changes

- **Ticker completeness**: Audit and fix why followed stocks are absent from the ticker. The most likely culprit is the AJAX refresh replacing SSR content with a subset; removing the poll is the first corrective step.
- **Remove AJAX polling**: Strip the `setInterval` timer and `refresh()`/`buildTrack()` fetch logic from `stock-ticker.js`. Page-load SSR data is sufficient; the ticker animates from that content without ever hitting `/api/ticker`.
- **Double ticker speed**: Halve the animation duration formula — `Math.max(itemCount * 3, 20)` → `Math.max(itemCount * 1.5, 10)` — so the full symbol list cycles in roughly half the time.
- **Market cap currency**: Finnhub's `marketCapitalization` field is denominated in the stock's local currency (millions). Store the `currency` field from the profile2 response and surface it in the stock detail view so users see, e.g., "TWD 60.00T" instead of a misleading "$60.00T".

## Capabilities

### New Capabilities
- `stock-market-cap-currency`: Market cap on the individual stock page is displayed with the correct currency code, preventing misinterpretation of foreign-currency values.

### Modified Capabilities
- `ticker-js-refresh`: Removing client-side polling entirely; JS responsibility narrows to setting animation duration from SSR item count on page load.

## Impact

- `public/stock-ticker.js` — remove polling, simplify to a single duration-setter
- `app/stock_quote_provider.rb` — store `currency` from Finnhub profile2
- `app/stock_quotes_store.rb` — add `currency` to upsert
- Database — `ALTER TABLE stock_quotes ADD COLUMN IF NOT EXISTS currency VARCHAR(10)`
- `app/main.rb` — update `format_market_cap` helper to accept and display currency
- `views/stock_detail.erb` — pass currency to the formatted value
- `spec/stocks_spec.rb` — update ticker specs to reflect no-poll behaviour
