## Context

The stock ticker is rendered server-side in `views/_stock_ticker.erb` using `ticker_quotes`, which correctly assembles all of a user's followed symbols plus 10 major indices. The rendered HTML is accurate on first load.

Turbo 8 caches full-page snapshots in memory. On subsequent navigation to a previously-visited page, Turbo immediately shows the cached snapshot as a "preview" before the fresh response arrives. If the user followed additional stocks after the snapshot was taken, the ticker in the snapshot is missing those symbols. The fresh response eventually replaces it — but Turbo's replacement triggers a DOM swap that resets the CSS animation, which is what the user perceives as a "reload."

Turbo's `data-turbo-permanent` attribute prevents this: an element marked permanent is kept from the **current live DOM** across Turbo navigations instead of being replaced by either the cached snapshot or the incoming fresh response. The first correct render (which includes all follows) stays in the DOM for the duration of the session.

## Goals / Non-Goals

**Goals:**
- All followed symbols appear in the ticker and never silently disappear due to a Turbo cache snapshot
- The CSS animation never resets due to a Turbo-driven DOM swap
- JS init still correctly sets `animationDuration` after the permanent element is adopted on first load

**Non-Goals:**
- Live-updating the ticker mid-session when the user adds a new follow (a full page reload already handles this)
- Changing the data source or the `ticker_quotes` helper

## Decisions

**Use `data-turbo-permanent` on `#stock-ticker`**

Alternatives considered:
- `<meta name="turbo-cache-control" content="no-cache">` in the layout — disables caching site-wide, hurts navigation performance for all other content
- `<meta name="turbo-cache-control" content="no-preview">` — suppresses the snapshot preview, adds a visible loading gap on every navigation
- Turbo Frame lazy-load (`src="/stocks/ticker-frame"`) — adds an extra HTTP round trip per navigation just for the ticker

`data-turbo-permanent` on `#stock-ticker` is surgical: it only affects this element and keeps zero additional network requests. Turbo simply promotes the element from the current DOM into the incoming page without a round trip.

**Remove `dataset.tickerInited` sentinel from JS**

With `data-turbo-permanent`, the `#stock-ticker` element is NOT replaced on Turbo navigation — it persists. `DOMContentLoaded` fires once (on the first full page load). `turbo:load` fires on every navigation, but since the permanent element already has `animationDuration` set from the initial `DOMContentLoaded` call, re-running `init()` is a no-op (it reads the same items and sets the same duration). The sentinel is not harmful but is unnecessary; removing it simplifies the code.

## Risks / Trade-offs

- **Stale ticker during session**: If the user follows a new stock, the permanent ticker won't update until a full page reload. This is acceptable because a full reload occurs naturally after the follow action (the follow form POSTs and redirects, triggering a non-Turbo navigation).
- **Turbo version assumption**: `data-turbo-permanent` has been stable since Turbo 7. The app bundles `public/turbo.js` locally — no external version dependency to manage.

## Migration Plan

1. Add `data-turbo-permanent` attribute to `<section id="stock-ticker">` in `views/_stock_ticker.erb`
2. Simplify `public/stock-ticker.js` to remove the sentinel guard
3. Deploy — no migration or rollback risk; attribute is purely additive
