## ADDED Requirements

### Requirement: Ticker element persists across Turbo navigations
The `<section id="stock-ticker">` element SHALL carry `data-turbo-permanent` so Turbo keeps the live instance in the DOM instead of replacing it with a cached page snapshot or the incoming response's version. This guarantees the ticker always reflects the content from the most recent full-page render, not a stale snapshot.

#### Scenario: Navigation after following a new stock
- **WHEN** the user follows a new stock and then navigates between pages using Turbo
- **THEN** the ticker shows the same symbols as on the page where the follow was completed
- **THEN** the ticker does not reset to a snapshot that predates the new follow

#### Scenario: CSS animation is not reset on navigation
- **WHEN** the user navigates between pages using Turbo
- **THEN** the ticker's CSS animation continues without resetting to position 0
- **THEN** no visible "refresh" or jump occurs in the scrolling animation

#### Scenario: All followed symbols remain visible
- **WHEN** a signed-in user with N followed symbols loads any page
- **THEN** all N symbols appear in the `#stock-ticker` element's HTML
- **THEN** Turbo navigation does not remove any of those symbols from the DOM
