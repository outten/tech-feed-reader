## Why

The `/pbs` page lists subscribed shows and recent episodes, but there's no way to drill into a single show. Every show card links nowhere — the user can't browse all episodes for "NOVA" or "Frontline" separately. Each article links to `/article/:uid` for reading, but there's no consolidated per-show episode list.

## What Changes

- **`/pbs` view**: Each show name in "My PBS" becomes a link to `/pbs/:feed_id`, the new show detail page.
- **New route `GET /pbs/:feed_id`**: Returns all recent articles for a single PBS feed, ordered newest first.
- **New view `views/pbs_show.erb`**: Lists every episode/article for the show. Each item has:
  - Title linking to `/article/:uid` (in-app reading view)
  - "▶ Listen" button if `audio_url` is present (opens audio player via `/article/:uid`)
  - "▶ Watch" button if the article URL is a YouTube link (opens YouTube in a new tab)
  - "Read →" link for text-only articles
  - Publication date and duration (if applicable)

## Capabilities

### New Capabilities
- `pbs-show-detail`: A per-show episode list at `/pbs/:feed_id` that lets users browse and consume all content from a single PBS show.

## Impact

- `app/main.rb` — one new route (`GET /pbs/:feed_id`)
- `views/pbs.erb` — show names in "My PBS" section become links
- `views/pbs_show.erb` — new view (new file)
- No schema changes, no new dependencies
