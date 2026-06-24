## Why

The stock ticker does not reliably show all symbols the signed-in user is following. Previous fixes (polling removal, JS fetch, SSR-only) did not resolve the issue. Root cause analysis points to Turbo's page-preview cache serving a stale snapshot of the ticker (from a previous visit with fewer follows) before the fresh server response arrives — causing followed symbols added since that visit to appear missing.

## What Changes

- Mark `#stock-ticker` as `data-turbo-permanent` so Turbo keeps the first correctly-rendered instance across navigations instead of substituting a stale cached snapshot
- Add a test that verifies all followed symbols appear in the rendered layout HTML, exercising the full `ticker_quotes` → `_stock_ticker.erb` pipeline

## Capabilities

### New Capabilities
- `ticker-permanent`: Stock ticker element is marked permanent in Turbo so its content is never replaced by a stale page-cache snapshot during navigation

### Modified Capabilities
- `ticker-js-refresh`: JS init no longer guards against double-fire via `data-tickerInited` sentinel on the ticker element (permanent elements are not re-rendered by Turbo, so the sentinel is unnecessary)

## Impact

- `views/_stock_ticker.erb`: add `data-turbo-permanent` to `<section id="stock-ticker">`
- `public/stock-ticker.js`: remove the `dataset.tickerInited` guard (permanent elements are swapped in by Turbo, not re-created — the sentinel would block duration from being set after the element is adopted)
- `spec/stocks_spec.rb`: add integration test covering all followed symbols in rendered HTML
