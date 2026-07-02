## Context

The app has topic-specific per-feed content pages (`/youtube/:feed_id`, `/pbs/:feed_id`) but no generic equivalent. `/feeds` is a management page in a dropdown menu. Users can't easily navigate to content from a specific feed without going through topic-specific silos.

## Goals / Non-Goals

**Goals:**
- Surface "Feeds" as a first-class nav destination alongside Articles and Bookmarks
- Let users drill from the feeds list into per-feed content in one click
- Reuse the established podcast-card layout and action pattern (Listen/Watch/Read)

**Non-Goals:**
- Redesigning the `/feeds` management UI (catalog, AI recommender, mute rules stay as-is)
- Pagination on the per-feed page (50-item limit matches `/pbs/:feed_id`)
- Unifying with topic-specific feed pages (`/youtube/:feed_id`, `/pbs/:feed_id` remain)

## Decisions

**Reuse `/feeds` as the list page**: The existing page already shows the user's subscriptions. We only need to make feed titles link to `/feeds/:feed_id` and add it to the top nav — no data or routing changes on the list side.

**Route `/feeds/:feed_id` as a generic guard**: Unlike `/youtube` and `/pbs` routes which check topic/URL pattern, this route just verifies subscription ownership (user must be subscribed). No topic restriction — it works for any feed.

**Podcast-card layout for content**: `views/feed_show.erb` mirrors `views/pbs_show.erb` — podcast-card list with Listen (audio), Watch (YouTube URL), or Read actions. Same logic, no new CSS classes needed.

**Active state in nav**: "Feeds" link is active on `/feeds` and `/feeds/*`. The existing `browse_active` check is unrelated; Feeds goes in the primary nav level (like Articles/Bookmarks), not the Browse dropdown.

## Risks / Trade-offs

**`/feeds/:feed_id` route order**: Sinatra matches routes top-down. The existing `POST /feeds/...` routes are fine (different verb). The new `GET /feeds/:feed_id` must be placed after all existing `GET /feeds/...` fixed routes to avoid `:feed_id` consuming `/feeds/catalog/add` etc. → Add it after `GET /feeds` and `POST /feeds/ai-recommend`.

**`/feeds` already in Manage dropdown**: Leaving the Manage dropdown link in place avoids breaking nav muscle memory for power users. The top-level link is additive. → No removal needed.
