## Why

Users have no way to browse all their subscribed feeds in one place and click through to read content from a specific feed. `/feeds` is buried in the Manage dropdown and is a management-only page; there is no per-feed content view outside of topic-specific silos (YouTube, PBS, Podcasts).

## What Changes

- **Promote `/feeds` to top-level nav**: Add a "Feeds" link in the primary nav bar alongside Articles and Bookmarks. The existing `/feeds` page already lists subscriptions; make feed titles link to the new per-feed content page.
- **New `/feeds/:feed_id` route**: Per-feed content page showing the most recent articles/episodes for a subscribed feed with Listen / Watch / Read engage actions. Reuses the podcast-card layout already established by `/pbs/:feed_id`.
- **Feed titles become links**: In the "My Subscriptions" section of `/feeds`, each feed title links to `/feeds/:feed_id` so users can drill down.

## Capabilities

### New Capabilities
- `feed-detail-page`: `/feeds/:feed_id` — content listing for a single subscribed feed. Renders up to 50 recent items with Listen/Watch/Read actions. Guards against unsubscribed or unknown feeds (404).

### Modified Capabilities
- (none — `/feeds` page behavior unchanged beyond feed titles becoming links)

## Impact

- `views/layout.erb` — add top-level "Feeds" nav link; update `browse_active` / active-state logic
- `app/main.rb` — add `GET /feeds/:feed_id` route
- `views/feed_show.erb` — new view (per-feed episode/article list, podcast-card layout)
- `views/feeds.erb` — feed titles in "My Subscriptions" section become `<a href="/feeds/:id">`
- `spec/feed_show_spec.rb` — new spec covering 200/404 and action link rendering
