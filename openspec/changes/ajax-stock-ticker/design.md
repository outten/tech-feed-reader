## Context

The stock ticker is a CSS `animation: ticker-scroll` marquee rendered server-side in `views/_stock_ticker.erb` on every layout render. Data comes from `ticker_quotes` (a memoized Sinatra helper that reads `stock_quotes` and `stock_follows` from PG). Two problems:

1. **Silent data drops**: `ticker_quotes` silently omits any symbol (especially major indices) whose quote row isn't yet in `stock_quotes`. Indices are refreshed by `IndexSyncWorker` (hourly) and `StockSyncWorker` (every 15 min); if Sidekiq was down or the cache is cold, users see 0–2 items instead of their full list.

2. **`data-turbo-permanent` stale data**: The element is kept alive across Turbo navigations, so the ticker never gets fresh data until a hard reload. Cache could warm up mid-session and the user would never see the update.

The ticker element lives in the layout, fires on every signed-in page, and must not cause layout shift or flicker.

## Goals / Non-Goals

**Goals:**
- Every followed symbol + all 10 major indices always appear in the ticker (with name-only fallback when quote cache is cold).
- Ticker data refreshes in-session without requiring a page reload.
- No flash of empty content on load (SSR provides the cold-start baseline).
- Animation continues smoothly; a refresh replaces items gracefully.

**Non-Goals:**
- Real-time tick-by-tick price streaming (15-min polling is sufficient).
- Changing the visual design of the ticker.
- Supporting unauthenticated users (ticker is sign-in-only).

## Decisions

### 1. Client-side polling via `/api/ticker` JSON endpoint

**Decision**: Add `GET /api/ticker` returning JSON. A new `stock-ticker.js` polls it on a 5-minute timer and rebuilds the track DOM in-place.

**Alternatives considered**:
- **Turbo Frame auto-refresh** (`<turbo-frame refresh="interval">`) — would re-request the full frame HTML; simpler JS surface but requires ERB changes and Turbo 8 frame-refresh feature. Rejected: less control over animation continuity.
- **Fix SSR only** (include index placeholders, remove `data-turbo-permanent`) — solves the data-drop bug but not the stale-data-on-navigation bug. Users navigating all session would see pre-warmup data indefinitely. Rejected as incomplete.
- **WebSocket / SSE push** — overkill for stock quotes that change at most every 15 min. Rejected.

### 2. SSR content as cold-start baseline; JS enhances, doesn't replace

**Decision**: Keep the server-side render in `_stock_ticker.erb`. The JS checks if the ticker already has content on `DOMContentLoaded`/`turbo:load` and skips the first network fetch if items are present, polling only on the interval after that.

**Rationale**: Avoids flash of empty content and keeps the ticker functional when JS is slow to load.

### 3. Fix `ticker_quotes` to include all index placeholders

**Decision**: Build a lookup from `StockQuoteProvider::MAJOR_INDICES` and use it as a third fallback (after `by_sym` and `followed_by_sym`). Every symbol in `ordered` always yields a row.

```ruby
index_by_sym = StockQuoteProvider::MAJOR_INDICES
                 .each_with_object({}) { |i, h| h[i[:symbol]] = i }

ordered.filter_map do |s|
  by_sym[s] ||
    (followed_by_sym[s] && { 'symbol' => s, 'name' => followed_by_sym[s]['name'] }) ||
    (index_by_sym[s]    && { 'symbol' => s, 'name' => index_by_sym[s][:name] })
end
```

This fixes SSR cold-start and makes `/api/ticker` consistent without extra DB queries.

### 4. Remove `data-turbo-permanent`; accept animation reset on navigation

**Decision**: Drop `data-turbo-permanent`. With JS polling, stale SSR content is a non-issue — the ticker is re-rendered by the new page's SSR on each Turbo navigation. The animation restarts from the beginning, which is acceptable (the ticker is decorative, not mid-read content).

**Rationale**: Keeping `data-turbo-permanent` with client-side refresh would cause a jarring flicker when JS updates the DOM while the permanent node is preserved. Simpler to let Turbo replace the whole section.

### 5. Animation-duration managed in JS after each data refresh

**Decision**: Remove the inline `animation-duration` style from ERB. After each data load, JS calculates `Math.max(items.length * 3, 20)` seconds and sets it on the track element. The CSS baseline (`30s`) applies until JS runs.

## Risks / Trade-offs

- **Extra HTTP request per 5-min interval** — minimal; the response is small JSON (~500 bytes for 15 symbols). Risk: negligible.
- **Animation jitter on refresh** — rebuilding `.stock-ticker-track` innerHTML resets the animation mid-scroll. Mitigation: recalculate animation-duration and set `animation: none; reflow; animation: ...` idiom to restart cleanly from position 0. Alternatively, only update items that changed (diff by symbol). Simplest: accept the reset every 5 min since it's rare and quick.
- **JS init double-fire** (Turbo 8) — `DOMContentLoaded` + `turbo:load` both fire on full page loads. Use a `data-ticker-inited` sentinel on the section to prevent double-init (established pattern in this codebase).

## Migration Plan

1. Fix `ticker_quotes` → deploy (SSR improvement is immediately active).
2. Add `/api/ticker` endpoint → included in same deploy.
3. Add `stock-ticker.js` + wire in layout → same deploy.
4. No rollback complexity — if JS fails, SSR ticker still shows with placeholder names; no data migration needed.
