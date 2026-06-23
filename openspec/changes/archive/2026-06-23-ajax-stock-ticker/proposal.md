## Why

The global stock ticker fails to show all of the user's followed stocks and major world indices because it depends on `stock_quotes` cache rows that may not exist yet (Sidekiq was down), and once rendered with `data-turbo-permanent` it never refreshes its data across Turbo navigations. Users open the app and see a partial or empty ticker even though their follows are configured correctly.

## What Changes

- Replace the server-rendered, static ticker with a client-side component that fetches data via a new JSON endpoint and refreshes itself on a timer.
- Add `GET /api/ticker` — returns the full ordered list of followed symbols + major indices, always including every symbol (with a name-only placeholder when the quote cache is cold), never dropping items silently.
- Remove the inline `animation-duration` calculation from the ERB template (move into JS so it stays accurate after a data refresh).
- Remove `data-turbo-permanent` from the ticker section — the JS refresh makes stale SSR data unnecessary; the animation reset on navigation is tolerable (or handled in JS).
- Keep the existing `ticker_quotes` server-side helper for the initial SSR render (no flash of empty content on load).

## Capabilities

### New Capabilities
- `ticker-api`: JSON endpoint `/api/ticker` that returns ordered quote data for the signed-in user's ticker (followed stocks first, then major indices, always including every symbol).
- `ticker-js-refresh`: Client-side JS that boots the ticker animation from SSR content, then polls `/api/ticker` on a timer and reconciles the DOM without resetting the animation position.

### Modified Capabilities
- (none — `ticker_quotes` helper stays; only the view and CSS animation-duration wiring change)

## Impact

- **New route**: `GET /api/ticker` in `app/main.rb` — JSON, auth-gated, same logic as `ticker_quotes`.
- **`ticker_quotes` helper**: Minor fix — include index symbols as name-only placeholders even when not cached (using `StockQuoteProvider::MAJOR_INDICES` names), so SSR and API both guarantee all symbols appear.
- **`views/_stock_ticker.erb`**: Remove inline `animation-duration` style; keep SSR content as the cold-start baseline.
- **New JS file `public/stock-ticker.js`**: Polls `/api/ticker`, updates `.stock-ticker-track` items, recalculates animation-duration.
- **`views/layout.erb`**: Wire in `stock-ticker.js` with `asset_mtime`.
- **`public/style.css`**: No structural changes; animation-duration default (30s) stays as the CSS baseline.
- No new dependencies, no schema changes.
