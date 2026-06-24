## MODIFIED Requirements

### Requirement: Ticker JS module initializes from SSR content
`stock-ticker.js` SHALL initialize the ticker from existing SSR-rendered DOM content on page load. It SHALL set `animationDuration` on the `.stock-ticker-track` based on the number of `.stock-ticker-item` elements present (divided by 2, since the track is duplicated). It SHALL NOT use a sentinel attribute to guard against double-init — the `data-turbo-permanent` attribute on `#stock-ticker` ensures the element is never re-rendered by Turbo, making the guard unnecessary.

#### Scenario: First load with SSR content present
- **WHEN** the page loads and `#stock-ticker` has `.stock-ticker-item` children
- **THEN** JS sets `animationDuration = Math.max(itemCount / 2 * 1.5, 10) + 's'` on the track
- **THEN** no network request is made

#### Scenario: Turbo navigation (permanent element adopted)
- **WHEN** the user navigates to a new page via Turbo
- **THEN** the permanent `#stock-ticker` element is adopted into the new page's DOM unchanged
- **THEN** `turbo:load` fires and `init()` runs again — it reads the same items and sets the same duration (idempotent, no visible effect)

## REMOVED Requirements

### Requirement: Ticker JS polls /api/ticker and updates the DOM
**Reason**: Polling was removed because the server-side render already provides the complete, correct, user-specific ticker on every page load. Polling caused the CSS animation to reset on each fetch, which was perceived as an unwanted "refresh."
**Migration**: None — the ticker is now purely SSR-driven. Price data is as fresh as the last background sync job run.

### Requirement: Double-fire sentinel guard
**Reason**: The `data-turbo-permanent` attribute on `#stock-ticker` makes the sentinel unnecessary. The permanent element is adopted (not re-rendered) on Turbo navigations, so double-init cannot produce stale or incorrect state.
**Migration**: Remove `section.dataset.tickerInited` check from `stock-ticker.js`.
