## 1. Route

- [x] 1.1 In `app/main.rb`, add `GET /pbs/:feed_id` immediately after the `GET /pbs` route (before the YouTube section). Validate: feed exists, user is subscribed, `feed['topic'] == 'pbs'`. Assign `@page_title`, `@articles` (via `ArticlesStore.for_feed(current_user_id, @feed['id'], limit: 50)`), render `:pbs_show`.

## 2. View — pbs_show.erb

- [x] 2.1 Create `views/pbs_show.erb`. Include:
  - Back link `← PBS` pointing to `/pbs`
  - Show header: image (if `@feed['image_url']` present), title, feed URL as muted subtitle
  - Episode count (`@articles.length`)
  - `<ul class="podcast-episodes">` list using `.podcast-card` structure (match the card layout already used in `views/pbs.erb` lines 18–52)
  - Per-article action: "▶ Listen" → `/article/:uid` if `audio_url` present; "▶ Watch" → external `url` with `target="_blank"` if URL contains `youtube.com` or `youtu.be`; otherwise "Read →" → `/article/:uid`
  - Empty state paragraph if `@articles.empty?`

## 3. pbs.erb — link show titles

- [x] 3.1 In `views/pbs.erb` "My PBS" section (line ~62), change `<span class="catalog-title">` to `<a class="catalog-title" href="/pbs/<%= feed['id'] %>">` (closing `</a>` instead of `</span>`).

## 4. Tests

- [x] 4.1 Add a spec asserting `GET /pbs/:feed_id` returns 200 for a subscribed PBS feed and includes the feed title and article titles.
- [x] 4.2 Add a spec asserting `GET /pbs/:feed_id` returns 404 for a non-PBS feed (wrong topic).
- [x] 4.3 Add a spec asserting the show detail page includes a "▶ Listen" link for audio articles and a "Read →" link for text-only articles.
