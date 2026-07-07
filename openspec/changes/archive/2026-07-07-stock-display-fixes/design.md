## Context

Four targeted fixes across two subsystems: the stock ticker bar and the individual stock detail page.

---

## Fix 1 — Ticker completeness (remove AJAX polling)

**Root cause hypothesis**: `stock-ticker.js` starts a `setInterval` that fires `refresh()` every 5 minutes, which replaces the SSR-rendered ticker content with what `/api/ticker` returns. If that API call fails silently (network hiccup, session expiry) the replacement may omit items; if it succeeds but the session is stale, `ticker_quotes` returns `[]` and all items disappear. The SSR render on page load is reliable — removing the poll eliminates the attack surface.

**Decision**: Strip the AJAX layer from `stock-ticker.js` entirely. The module's sole responsibility becomes reading the SSR `.stock-ticker-item` count and calling `setDuration`. No `fetch`, no `buildTrack`, no `setInterval`.

**Resulting `stock-ticker.js` shape:**
```javascript
(function () {
  let inited = false;
  function init() {
    const section = document.getElementById('stock-ticker');
    if (!section || inited) return;
    inited = true;
    const track = section.querySelector('.stock-ticker-track');
    const items = track ? track.querySelectorAll('.stock-ticker-item') : [];
    if (items.length) setDuration(track, items.length / 2);
  }
  function setDuration(track, count) {
    track.style.animationDuration = Math.max(count * 1.5, 10) + 's';
  }
  document.addEventListener('DOMContentLoaded', init);
  document.addEventListener('turbo:load', init);
}());
```

The `inited` guard remains because both `DOMContentLoaded` and `turbo:load` fire on full page loads (Turbo 8 double-fire pattern).

`GET /api/ticker` stays in the route table — it has tests and no cost to keep — but is no longer called by any JS.

---

## Fix 2 — Double ticker speed

**Current formula**: `Math.max(itemCount * 3, 20) + 's'`
**New formula**: `Math.max(itemCount * 1.5, 10) + 's'`

At 15 symbols this goes from 45 s → 22.5 s per full cycle. The minimum drops from 20 s → 10 s for very short symbol lists.

This change lives entirely in `setDuration` above — no CSS changes needed.

---

## Fix 3 — Market cap currency

**Root cause**: Finnhub's `/stock/profile2` endpoint returns `marketCapitalization` in **millions of the stock's home-market currency**, not necessarily USD. For TSM (listed on the TWSE), this is TWD millions. The app multiplies by 1,000,000 and formats with a `$` prefix, yielding a misleading `$60T`.

**Decision**: Store the `currency` field from the Finnhub profile2 response alongside market cap. Display it in `format_market_cap` so users see `TWD 60.00T` instead of `$60.00T`.

### Database

```sql
ALTER TABLE stock_quotes ADD COLUMN IF NOT EXISTS currency VARCHAR(10);
```

No migration file needed — this project uses `IF NOT EXISTS` guards applied at app boot or manually. Add to the schema bootstrap in `db/schema.sql` (or equivalent) so future fresh installs pick it up.

### `stock_quote_provider.rb`

```ruby
data.merge!(
  name:       p['name'],
  exchange:   p['exchange'],
  sector:     p['finnhubIndustry'],
  industry:   p['finnhubIndustry'],
  market_cap: p['marketCapitalization'] ? (p['marketCapitalization'].to_f * 1_000_000).to_i : nil,
  currency:   p['currency'],
  logo:       p['logo']
)
```

### `stock_quotes_store.rb`

`currency` is already accepted by the variadic `**data` in `upsert` — no change needed there, but verify the `INSERT` column list includes it.

### `app/main.rb` — `format_market_cap`

```ruby
def format_market_cap(val, currency = 'USD')
  return '—' if val.nil?
  v    = val.to_i
  sym  = currency.to_s.upcase == 'USD' ? '$' : ''
  sfx  = currency.to_s.upcase == 'USD' ? '' : " #{currency.to_s.upcase}"
  if    v >= 1_000_000_000_000 then format("#{sym}%.2fT#{sfx}", v / 1_000_000_000_000.0)
  elsif v >= 1_000_000_000     then format("#{sym}%.2fB#{sfx}", v / 1_000_000_000.0)
  elsif v >= 1_000_000         then format("#{sym}%.2fM#{sfx}", v / 1_000_000.0)
  else  "#{sym}#{v}#{sfx}"
  end
end
```

USD stays as `$1.23T`. Non-USD appears as `TWD 60.00T`, `EUR 1.23B`, etc.

### `views/stock_detail.erb`

```erb
<span class="summary-value"><%= format_market_cap(@quote['market_cap'], @quote['currency']) %></span>
```

---

## Risks / Trade-offs

- **Ticker completeness**: Removing the poll means data does NOT refresh during a long session. Acceptable — stock prices are best seen by reloading the page; the ticker is decorative context, not a trading terminal.
- **Currency display**: Existing rows in `stock_quotes` have `NULL` for `currency` after the migration. `format_market_cap` receives `nil`, which `to_s.upcase` makes `""` — falls through to the `else` branch and displays without prefix. A quick re-sync of affected symbols (e.g., by re-following or waiting for the next `StockSyncWorker` run) will populate the column.
- **DB column**: `ADD COLUMN IF NOT EXISTS` is safe and instant on an empty or lightly populated table.
