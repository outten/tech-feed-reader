## Context

`load_whats_on_today!` in `app/main.rb` (lines 686–700) builds `@today_watching` from two steps:

1. `scored = Recommendation::ForYou.score_window(...)` — top 200 scored articles (all time)
2. `todays = scored.select { published_at >= midnight_utc }` — filter to today
3. Partition by YouTube URL → `@today_watching = videos_today.first(10)`

Channels that didn't post today contribute 0 videos. The fix adds a fallback pass after step 3: for each subscribed YouTube channel not yet represented in `@today_watching`, fetch its most recent article and append it (up to the 10-video cap).

`ArticlesStore` already has `youtube_channels(user_id)` which queries subscribed channels via `YOUTUBE_FEED_URL_PATTERN = '%youtube.com/feeds/videos.xml%'`. That method returns feed-level rows with `latest_uid`/`latest_url` but not full article rows. We need a companion method that returns the actual article row for the latest video per missing channel.

## Goals / Non-Goals

**Goals:**
- Every subscribed YouTube channel shows at least one video on the home page.
- Channels that already posted today keep their ranked position; fallback videos fill remaining slots.
- Fallback videos are the most recent article from that channel, regardless of publish date or read state.

**Non-Goals:**
- Changing the total cap (still 10 videos max).
- Changing how today's videos are ranked or scored.
- Adding a "from N days ago" label to fallback videos (the existing relative timestamp covers it).

## Decisions

**One new ArticlesStore method: `latest_youtube_videos_for_channels(user_id, exclude_feed_ids:)`**

Returns one article row per subscribed YouTube channel whose feed_id is NOT in `exclude_feed_ids`, ordered by latest `published_at`. Uses PostgreSQL `DISTINCT ON (f.id)` for efficient one-per-channel selection.

```sql
SELECT DISTINCT ON (f.id)
       a.id, a.uid, a.title, a.url, a.published_at,
       a.feed_id, a.audio_url, a.content_text
FROM articles a
JOIN feeds f ON f.id = a.feed_id
JOIN user_feed_subscriptions ufs ON ufs.feed_id = f.id AND ufs.user_id = ?
WHERE f.url LIKE ?
  AND f.id NOT IN (...)         -- already covered by today's videos
  AND (a.url LIKE '%youtube.com%' OR a.url LIKE '%youtu.be%')
ORDER BY f.id, a.published_at DESC NULLS LAST, a.id DESC
```

If `exclude_feed_ids` is empty, the `NOT IN` clause is omitted (avoids `NOT IN ()`).

**Merging in `load_whats_on_today!`**

After the existing line 700:
```ruby
@today_watching = videos_today.first(10)
```

Add:
```ruby
if @today_watching.length < 10
  covered_feed_ids = @today_watching.map { |a| a['feed_id'] }.uniq
  fallbacks = ArticlesStore.latest_youtube_videos_for_channels(
    current_user_id, exclude_feed_ids: covered_feed_ids
  )
  slots = 10 - @today_watching.length
  @today_watching = @today_watching + fallbacks.first(slots)
end
```

**No changes to the view** — `home.erb` already renders whatever is in `@today_watching`; fallback rows have the same fields as scored rows.

## Risks / Trade-offs

- **Channels with 0 articles**: If a newly subscribed channel has no ingested articles yet, `DISTINCT ON` returns nothing for it — no video shown, which is correct.
- **Performance**: One extra DB query per home page load, but it's a single indexed join with a small result set (one row per subscribed YouTube channel, typically < 20).
- **`NOT IN` with empty array**: Handled explicitly — if `@today_watching` already has 10 videos the fallback branch is skipped entirely.
