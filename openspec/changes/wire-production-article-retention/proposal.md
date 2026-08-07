## Why

`Pruner` (`app/pruner.rb`) already implements article retention — delete anything older than `RETENTION_DAYS` (default 7), always keeping bookmarks, optionally keeping unread articles — but it's only ever invoked from `scripts/refresh_feeds.rb` (the `make refresh-feeds` / `make scheduler` CLI path) or standalone via `make prune`. Production's `docker-compose.yml` runs neither of those; the hourly fetch there goes entirely through `RefreshAllFeedsWorker` / `FeedRefreshWorker` via `config/sidekiq_cron.yml`, and nothing in that path ever calls `Pruner`. Confirmed against production: **138,083 total articles**, including a webcomic feed's archive with `published_at` dates back to 2012 — the retention sweep has, in practice, never run there (STUFF.md #114).

## What Changes

- Add a `PruneArticlesWorker` (mirrors the existing `FixArticleLinksWorker` daily-cron pattern) that calls `Pruner.prune_old` and logs the result.
- Add a `prune_articles` entry to `config/sidekiq_cron.yml` so it actually runs on a schedule in production.
- ~~The automated worker defaults to preserving unread articles (`keep_unread: true`)~~ — **shipped this way first, then revised; see "Revision" below.** Measured against the real production data: with `keep_unread: false`, a first run would delete **123,436 of 138,083 articles (89%)** — including **121,660 unread articles** the user has never seen. With `keep_unread: true`, the same first run only removes **1,776 already-read, non-bookmarked articles** older than 7 days, and touches zero bookmarks. An unattended nightly job's *first-ever* run needed the safe default while the real growth rate was still unknown — see the Revision section for what changed once it was.
- Wire `RETENTION_DAYS` / `PRUNE_KEEP_UNREAD` into `docker-compose.yml`'s `sidekiq` service environment so the knobs are actually configurable in production (they currently aren't passed through at all).
- Run the very first prune manually (visible output, before the cron entry goes live) given this is a hard DELETE against a 138K-row table that's never been swept — not something to let an unattended job do unsupervised for the first time.

## Capabilities

### New Capabilities
- `article-retention-enforcement`: Production SHALL actually enforce the article retention policy the app already claims to have (`/admin` dashboard's "Activity (last N days)" label), on a recurring schedule. ~~without ever deleting an unread or bookmarked article~~ — revised: bookmarked articles remain permanently exempt; unread articles are now bounded to a 30-day window rather than exempt forever. See specs/article-retention-enforcement/spec.md.

### Modified Capabilities
(none — no existing spec covers article retention)

## Impact

- `app/workers/prune_articles_worker.rb` — new worker.
- `app/sidekiq_boot.rb` — require the new worker.
- `config/sidekiq_cron.yml` — new `prune_articles` cron entry.
- `docker-compose.yml` — `RETENTION_DAYS` / `PRUNE_KEEP_UNREAD` env vars for the `sidekiq` service.
- `app/pruner.rb` — no logic changes; only how it's invoked changes.
- ~~Explicitly out of scope: the unread backlog (136,057 of 138,083 articles) keeps growing indefinitely under this change~~ — **superseded, see Revision below.** This was the original intent (unread articles are `keep_unread`'s entire purpose), but shipping the safe version first is what made the follow-up decision possible: it surfaced the real growth rate (~2,000 articles/day) without risking the 121K-article backlog on an unreviewed guess.

## Revision — bounded retention instead of unread-forever

**Shipped first** (v1.1.27): `keep_unread: true`, hardcoded, no unread article ever deleted. This was deliberate — an unattended nightly job's first-ever run against a never-pruned 138K-row table needed the conservative default, not a guess.

**What changed:** with that safe version live, the real numbers came in: ~2,000 articles/day ingested, `articles` table already 1.5 GB of a 10 GiB managed-Postgres allocation, growing toward ~9 GB/year unbounded. That's a real, if not urgent, cost/capacity trajectory — worth capping deliberately rather than discovering it as an incident later.

**Decision:** flip `keep_unread` to `false` and raise `RETENTION_DAYS` from 7 to **30**. This is not "restore the dangerous default" — it's a distinct, reviewed choice: a 30-day reading window (not 7) that bounds the backlog to roughly a month of ingestion (~60,000 articles steady-state) instead of letting it grow forever. Bookmarks remain permanently exempt, unchanged.

Two scenarios were checked against live production data before deciding:
- **keep_unread stays `true`, just retention_days → 30**: `would_delete = 0`. Doesn't touch the actual problem — `retention_days` only ever governed read articles under `keep_unread: true`; unread growth continues unbounded regardless of this number. Rejected — solves nothing.
- **keep_unread → `false`, retention_days → 30** (chosen): `would_delete = 74,892` on first run (all currently-unread articles older than 30 days), settling to a bounded ~60,000-article steady state going forward.

See design.md's "Decision 2 (revised)" for the full reasoning and the DB-size grounding that motivated this.
