## Why

The "To watch today" section on the home page only shows YouTube videos published since midnight UTC. If a subscribed channel hasn't posted today — or posted outside the time window — it shows nothing from that channel. For channels that publish infrequently (weekly, bi-weekly), users may go days or weeks without ever seeing their content on the home page, even though they explicitly subscribed.

The fix: guarantee that every subscribed YouTube channel gets at least one video slot in "To watch today", using its most recent video even if it was published in the past.

## What Changes

- **`app/main.rb` `load_whats_on_today!`**: After collecting today's YouTube videos from the existing scored window, query for the most recent unread video from each subscribed YouTube channel that hasn't already contributed a video to the list. Append those fallback videos (one per missing channel) to `@today_watching`, up to the existing 10-video cap.
- The existing "For You" scoring and today's videos continue to take priority — fallbacks only fill slots not already occupied.

## Capabilities

### Modified Capabilities
- `youtube-home-section`: The "To watch today" section now guarantees at least one video per subscribed YouTube channel. Channels with no video published today contribute their most recent video as a fallback.

## Impact

- `app/main.rb` — `load_whats_on_today!` method only
- One additional DB query (subscribed YouTube channels + latest video per channel)
- No schema changes, no new dependencies
