## MODIFIED Requirements

### Requirement: Ticker JS fetches user-specific data once per page load
`stock-ticker.js` SHALL fetch `GET /api/ticker` exactly once on each page load/navigation and rebuild the `.stock-ticker-track` from the response. This ensures the ticker reflects the signed-in user's actual follows regardless of SSR state. There is NO polling interval — the fetch happens once per init.

#### Scenario: Page load — SSR content present (common case)
- **WHEN** the page loads and `#stock-ticker` has `.stock-ticker-item` children from SSR
- **THEN** JS immediately sets `animation-duration` from the SSR item count so the ticker animates while the fetch is in flight
- **THEN** JS fetches `/api/ticker` once; on success, replaces track content with API data and recalculates duration

#### Scenario: Page load — cold SSR (no cached quotes)
- **WHEN** the page loads and `#stock-ticker` has no `.stock-ticker-item` children
- **THEN** JS fetches `/api/ticker` once; on success, builds and animates the track from the response

#### Scenario: Fetch failure
- **WHEN** `/api/ticker` returns an error or the request fails
- **THEN** the existing SSR content (if any) is left intact
- **THEN** no retry or polling occurs

#### Scenario: Double-fire guard (Turbo 8)
- **WHEN** both `DOMContentLoaded` and `turbo:load` fire on a full page load
- **THEN** the init function runs only once (guarded by `section.dataset.tickerInited`, a DOM attribute sentinel on the `#stock-ticker` element)
- **WHY `dataset` not a module-level flag**: on Turbo navigations, the body is replaced and `#stock-ticker` is a fresh element without the attribute, so init correctly re-runs per navigation. A module-level flag would block re-init on navigations.

#### Scenario: Turbo navigation
- **WHEN** the user navigates to a new page via Turbo Drive
- **THEN** the new `#stock-ticker` element (from SSR) has no `data-ticker-inited` attribute
- **THEN** init runs again, sets duration from new SSR count, fetches `/api/ticker`, updates content

### Requirement: No polling
`stock-ticker.js` SHALL NOT call `setInterval` or `setTimeout`. The ticker data is fetched once per page load only.

### Requirement: Animation speed
The animation duration formula SHALL be `Math.max(itemCount * 1.5, 10) + 's'`, where `itemCount` is the number of unique symbols (half of the duplicated DOM count for SSR, or the raw API item count when building from API data).
