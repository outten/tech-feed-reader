## 1. Fix ticker_quotes helper (SSR data completeness)

- [x] 1.1 In `ticker_quotes` (`app/main.rb`), build an `index_by_sym` lookup from `StockQuoteProvider::MAJOR_INDICES` (keyed by symbol, value is the index hash with `:name`)
- [x] 1.2 Update the `filter_map` block to use `index_by_sym[s]` as a third fallback: `by_sym[s] || (followed_by_sym[s] && {...}) || (index_by_sym[s] && { 'symbol' => s, 'name' => index_by_sym[s][:name] })`
- [x] 1.3 Update the existing RSpec test in `spec/stocks_spec.rb` to also assert that a major index symbol appears when its quote cache is absent

## 2. Add /api/ticker JSON endpoint

- [x] 2.1 Add `get '/api/ticker'` route in `app/main.rb` (near other `/api/stocks` routes); call `require_signed_in!` then return `json(ticker_quotes)` with `content_type :json`
- [x] 2.2 Add a spec in `spec/stocks_spec.rb` for `GET /api/ticker`: assert 200 + JSON array when signed in; assert 401 when not signed in; assert all 10 MAJOR_INDICES symbols appear in the response even with a cold cache

## 3. Remove data-turbo-permanent from ticker

- [x] 3.1 In `views/_stock_ticker.erb`, remove `data-turbo-permanent` from the `<section>` tag
- [x] 3.2 Remove the inline `style="animation-duration: ...s"` from the `.stock-ticker-track` div (JS will set this after each data load)

## 4. Create stock-ticker.js

- [x] 4.1 Create `public/stock-ticker.js` with an `init()` function guarded by `data-ticker-inited` sentinel on `#stock-ticker`
- [x] 4.2 On init: if `.stock-ticker-item` children exist (SSR content), set duration from item count and start the poll timer without an immediate fetch
- [x] 4.3 Implement `buildTrack(items)`: generates the duplicated HTML string for `.stock-ticker-track` (two passes, second with `aria-hidden="true" tabindex="-1"`), then sets `animation-duration` to `Math.max(items.length * 3, 20) + 's'`
- [x] 4.4 Implement `refresh()`: fetches `/api/ticker`, on success calls `buildTrack`, on failure leaves existing content unchanged
- [x] 4.5 Set the poll interval to `5 * 60 * 1000` ms (5 minutes) via `setInterval`
- [x] 4.6 Register `init()` on both `DOMContentLoaded` and `turbo:load` (Turbo 8 double-fire pattern)

## 5. Wire stock-ticker.js into layout

- [x] 5.1 In `views/layout.erb`, add `<script src="/stock-ticker.js?v=<%= asset_mtime('public/stock-ticker.js') %>"></script>` after the existing stock JS entries (near `stock-news.js`)
