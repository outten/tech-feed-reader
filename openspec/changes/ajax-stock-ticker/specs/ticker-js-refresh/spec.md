## ADDED Requirements

### Requirement: Ticker JS module initializes from SSR content
`stock-ticker.js` SHALL initialize the ticker from existing SSR-rendered DOM content on page load. It SHALL use a `data-ticker-inited` sentinel attribute on `#stock-ticker` to guard against double-init on Turbo full-page loads (where both `DOMContentLoaded` and `turbo:load` fire).

#### Scenario: First load with SSR content present
- **WHEN** the page loads and `#stock-ticker` has `.stock-ticker-item` children
- **THEN** JS sets `data-ticker-inited` and starts the polling timer without an immediate network request
- **THEN** the animation continues from the SSR-rendered content

#### Scenario: Double-fire guard
- **WHEN** both `DOMContentLoaded` and `turbo:load` fire on a full page load
- **THEN** the init function runs only once (guarded by `data-ticker-inited`)

### Requirement: Ticker JS polls /api/ticker and updates the DOM
`stock-ticker.js` SHALL poll `GET /api/ticker` every 5 minutes and rebuild the `.stock-ticker-track` innerHTML with fresh data. After each rebuild it SHALL recalculate and set the `animation-duration` on the track element using `Math.max(items.length * 3, 20)` seconds.

#### Scenario: Successful poll with new data
- **WHEN** the 5-minute timer fires and `/api/ticker` returns data
- **THEN** the `.stock-ticker-track` content is rebuilt with the latest items (duplicated twice for seamless loop)
- **THEN** `animation-duration` is recalculated based on the item count

#### Scenario: Poll failure (network error or non-200)
- **WHEN** `/api/ticker` returns an error or the request fails
- **THEN** the existing ticker content is left unchanged
- **THEN** the polling timer continues (next attempt in 5 minutes)

### Requirement: Ticker is wired into the layout
`stock-ticker.js` SHALL be loaded via `views/layout.erb` using the `asset_mtime` helper (consistent with other JS files in the project). It SHALL NOT use `<script defer>` inside a view file.

#### Scenario: Script included in layout
- **WHEN** a signed-in user loads any page
- **THEN** `stock-ticker.js` is included via the layout's asset script block with cache-busting via `asset_mtime`
