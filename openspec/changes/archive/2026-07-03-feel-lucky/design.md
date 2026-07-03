## Context

The header has a row of icon-utility buttons (Search, Bus, Refresh) rendered only for signed-in users. Bus mode (`/bus`) is the closest analog: a single query with a filter, rendered in podcast-card layout. `/lucky` follows the same pattern but with `ORDER BY RANDOM()` and no content-type filter.

## Goals / Non-Goals

**Goals:**
- One-click random discovery from anywhere in the app
- Cross-type: text articles, podcasts, YouTube videos all eligible
- Each page visit re-rolls (stateless — no saved seeds)

**Non-Goals:**
- Filtering by topic, type, or read/unread state (that defeats the "lucky" premise)
- Infinite scroll or pagination (50-item cap matches the spec)
- Weighting by recency or feed weight (pure random)

## Decisions

**`ORDER BY RANDOM()` in PostgreSQL**: Simple, correct, and fast enough for the user's subscription set (typically hundreds to low-thousands of articles). No need for a more complex reservoir-sampling approach at this scale.

**No caching / no Turbo prefetch**: Each GET must hit the DB to re-roll. Add `data-turbo-prefetch="false"` to the icon link (same as the Admin link) so hover doesn't pre-fetch and waste a roll.

**Dice icon (SVG)**: A simple six-face dice SVG inline in layout.erb, consistent with the bus and search icons (no external icon library).

**Podcast-card layout**: Reuses existing CSS classes (`podcast-episodes`, `podcast-card`, `btn-primary`, `btn-secondary`). Listen/Watch/Read action logic identical to `feed_show.erb`.

**Route placement**: After existing `/bus` route — no ordering constraints.

## Risks / Trade-offs

**`ORDER BY RANDOM()` is non-deterministic**: Revisiting `/lucky` gives a new set every time. This is the intended behavior, but it means the back button returns to the same page with a new roll, which could feel surprising. Acceptable for a "lucky" feature.
