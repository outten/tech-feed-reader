## Why

`Pruner` (`app/pruner.rb`) already implements article retention — delete anything older than `RETENTION_DAYS` (default 7), always keeping bookmarks, optionally keeping unread articles — but it's only ever invoked from `scripts/refresh_feeds.rb` (the `make refresh-feeds` / `make scheduler` CLI path) or standalone via `make prune`. Production's `docker-compose.yml` runs neither of those; the hourly fetch there goes entirely through `RefreshAllFeedsWorker` / `FeedRefreshWorker` via `config/sidekiq_cron.yml`, and nothing in that path ever calls `Pruner`. Confirmed against production: **138,083 total articles**, including a webcomic feed's archive with `published_at` dates back to 2012 — the retention sweep has, in practice, never run there (STUFF.md #114).

## What Changes

- Add a `PruneArticlesWorker` (mirrors the existing `FixArticleLinksWorker` daily-cron pattern) that calls `Pruner.prune_old` and logs the result.
- Add a `prune_articles` entry to `config/sidekiq_cron.yml` so it actually runs on a schedule in production.
- The automated worker defaults to preserving unread articles (`keep_unread: true`), overriding `Pruner.prune_old`'s own default of `false`. Measured against the real production data: with `keep_unread: false`, a first run would delete **123,436 of 138,083 articles (89%)** — including **121,660 unread articles** the user has never seen. With `keep_unread: true`, the same first run only removes **1,776 already-read, non-bookmarked articles** older than 7 days, and touches zero bookmarks. An unattended nightly job needs the safe default; a human running `make prune` interactively can already opt in via `PRUNE_KEEP_UNREAD=1`.
- Wire `RETENTION_DAYS` / `PRUNE_KEEP_UNREAD` into `docker-compose.yml`'s `sidekiq` service environment so the knobs are actually configurable in production (they currently aren't passed through at all).
- Run the very first prune manually (visible output, before the cron entry goes live) given this is a hard DELETE against a 138K-row table that's never been swept — not something to let an unattended job do unsupervised for the first time.

## Capabilities

### New Capabilities
- `article-retention-enforcement`: Production SHALL actually enforce the article retention policy the app already claims to have (`/admin` dashboard's "Activity (last N days)" label), on a recurring schedule, without ever deleting an unread or bookmarked article.

### Modified Capabilities
(none — no existing spec covers article retention)

## Impact

- `app/workers/prune_articles_worker.rb` — new worker.
- `app/sidekiq_boot.rb` — require the new worker.
- `config/sidekiq_cron.yml` — new `prune_articles` cron entry.
- `docker-compose.yml` — `RETENTION_DAYS` / `PRUNE_KEEP_UNREAD` env vars for the `sidekiq` service.
- `app/pruner.rb` — no logic changes; only how it's invoked changes.
- Explicitly out of scope: the unread backlog (136,057 of 138,083 articles) keeps growing indefinitely under this change — that's the existing, intentional "don't delete what the user hasn't seen" behavior, not something this change tries to solve.
