## 1. Make ticker permanent

- [x] 1.1 Add `data-turbo-permanent` to `<section id="stock-ticker">` in `views/_stock_ticker.erb`

## 2. Simplify JS

- [x] 2.1 Remove `section.dataset.tickerInited` sentinel check from `public/stock-ticker.js` (no longer needed with permanent element)

## 3. Tests

- [x] 3.1 Add integration test in `spec/stocks_spec.rb` verifying that when a user follows multiple symbols, all of them appear in the rendered layout HTML (testing the full `ticker_quotes` → `_stock_ticker.erb` pipeline)

## 4. Verify

- [x] 4.1 Run full test suite (`make test`) — all 1707 examples pass
