## Why

The daily News Trivia quiz intermittently fails to generate in production, with nothing crashing and nothing alerting. Confirmed directly against the Droplet's `sidekiq` container logs and the production database: `GenerateTriviaWorker` runs to completion every day (no exception, no dead job — the original hypothesis of a stale/duplicate Sidekiq process was investigated and ruled out). The real failure is silent: on 2026-07-22 and 2026-07-23, `TriviaGenerator.generate` returned `status: parse_error` because `TriviaStore.fetch_source_articles` fed it almost nothing — its `ORDER BY published_at DESC LIMIT 20` query, with no content-quality guard, was dominated by ~80+ items from feed 254 ("Three Word Phrase", a webcomic) whose upstream RSS reports a `published_at` clustered at/near "now" (a couple even in the future — `2026-08-01`, `2026-09-16`) while `content_text` is a handful of words of comic dialogue (`"*cough*"`, `"ha ha ha huhhhhgh"`, 4–60 chars). These content-free, fake-recent rows outrank genuine news in the sort and crowd it out of the top 20, starving Claude's context down to ~1,700 characters — too little to produce 3+ valid trivia questions. `ensure_today!` returns `nil`, `GenerateTriviaWorker` logs a `warn` and exits normally — no retry, no dead job, so the existing dead-job ntfy alert never fires. A manual `make generate-trivia` run at a different moment (after enough real news has published past that pinned timestamp) succeeds, which is why it looked like a cron-vs-CLI problem rather than a source-selection bug.

## What Changes

- Add a content-quality guard to `TriviaStore.fetch_source_articles` (`app/games/trivia_store.rb`) so low-substance/junk rows — regardless of which feed produces them — can never dominate the top-20 "recent articles" window used to seed trivia generation.
- Make a failed/skipped generation (i.e. `ensure_today!` returns `nil`, whether from a parse error or genuinely too little source content) surface as a same-day, actionable alert, since this failure mode completes the Sidekiq job "successfully" and never reaches the existing dead-job alerting path.
- Verify the fix against both the historical bad state (feed 254's pattern) and a normal day, so the specific `Three Word Phrase`-shaped failure is confirmed closed without over-fitting to that one feed.

## Capabilities

### New Capabilities
- `trivia-generation-reliability`: Daily News Trivia generation SHALL be resilient to low-content/junk source articles polluting the recent-articles pool, and any day it fails to produce a quiz SHALL be observable same-day, not just discoverable later by reading raw logs.

### Modified Capabilities
(none — no existing spec covers trivia generation or source-article selection)

## Impact

- `app/games/trivia_store.rb` — `fetch_source_articles` gains a minimum content-length filter (and any related query changes) so junk/near-empty articles can't crowd out real news.
- `app/workers/generate_trivia_worker.rb` — emit an alert when `ensure_today!` returns `nil`, so a failed/skipped generation is visible the same day.
- No database schema changes, no user-facing behavior changes to the trivia game itself — this only changes which articles are eligible as trivia source material.
