## 1. Simplify stock-ticker.js (remove polling, double speed)

- [x] 1.1 Rewrite `public/stock-ticker.js`: remove `POLL_MS`, `pollTimer`, and the `setInterval` call; restore `buildTrack()`, `esc()`, `formatPrice()`, `formatPct()` helpers for API-driven rendering; fetch `/api/ticker` once per init (no timer)
- [x] 1.2 In `setDuration`, change the formula from `Math.max(itemCount * 3, 20)` to `Math.max(itemCount * 1.5, 10)` to double animation speed
- [x] 1.3 Use `section.dataset.tickerInited` (DOM attribute sentinel) instead of a module-level `inited` flag so init re-runs correctly on each Turbo navigation while still guarding against double-fire on full page loads

## 2. Market cap currency — database

- [x] 2.1 Create `db/migrations-postgres/010_stock_quote_currency.sql` with `ALTER TABLE stock_quotes ADD COLUMN IF NOT EXISTS currency VARCHAR(10);`
- [x] 2.2 Apply the migration locally: `psql $DATABASE_URL -f db/migrations-postgres/010_stock_quote_currency.sql` (or equivalent `make db-migrate`)

## 3. Market cap currency — backend

- [x] 3.1 In `app/stock_quote_provider.rb`, add `currency: p['currency']` to the `data.merge!` block inside `fetch_and_cache`
- [x] 3.2 In `app/main.rb`, update `format_market_cap` to accept an optional `currency` parameter; for USD (or nil), prefix with `$`; for non-USD, omit `$` and append ` CURRENCY_CODE`
- [x] 3.3 In `views/stock_detail.erb`, change the market cap call to `format_market_cap(@quote['market_cap'], @quote['currency'])`

## 4. Update specs

- [x] 4.1 In `spec/stocks_spec.rb`, update ticker JS-refresh specs to assert no polling (no setInterval) and the new duration formula; remove any specs that tested `GET /api/ticker` being called by JS
- [x] 4.2 Add or update a unit test for `format_market_cap` with a non-USD currency (e.g., `format_market_cap(60_000_000_000_000, 'TWD')` → `'TWD 60.00T'`)

## 5. Verify

- [x] 5.1 Run `make test` and confirm all specs pass
