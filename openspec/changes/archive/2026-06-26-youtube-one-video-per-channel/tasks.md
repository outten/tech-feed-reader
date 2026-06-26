## 1. ArticlesStore — new query method

- [x] 1.1 In `app/articles_store.rb`, add `latest_youtube_videos_for_channels(user_id, exclude_feed_ids: [])` after the existing `youtube_channels` method. Uses `DISTINCT ON (f.id)` to return one article row per subscribed YouTube channel whose feed_id is not in `exclude_feed_ids`. Omit the `NOT IN` clause when `exclude_feed_ids` is empty.

## 2. Home page logic

- [x] 2.1 In `app/main.rb` `load_whats_on_today!`, after `@today_watching = videos_today.first(10)` (line ~700): if `@today_watching.length < 10`, call `ArticlesStore.latest_youtube_videos_for_channels` with the already-covered feed_ids as `exclude_feed_ids`, then append fallback rows to fill remaining slots up to 10.

## 3. Tests

- [x] 3.1 In `spec/whats_on_spec.rb`, add a test: subscribe to a YouTube channel, add an article from last week; home page shows it in `@today_watching` even though it wasn't published today.
- [x] 3.2 Add a test: subscribe to two YouTube channels; one posts today, one doesn't — both appear in `@today_watching`.
- [x] 3.3 Add a test: when today's videos already fill all 10 slots, no fallback query runs (or at least no extra videos are shown beyond 10).
