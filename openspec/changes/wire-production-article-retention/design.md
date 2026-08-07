## Context

`Pruner.prune_old` (`app/pruner.rb`) is a straight, cascading `DELETE FROM articles WHERE ... < cutoff AND NOT (bookmarked OR (keep_unread AND unread))`. It's correct and already spec-tested (existing `Pruner` behavior isn't changing in this proposal), but it has never run against the production database — production's `docker-compose.yml` only runs `app`, `sidekiq`, `redis`, `caddy`, and the only two places `Pruner` is invoked (`scripts/refresh_feeds.rb`, `make prune`) aren't part of that stack. Production ingestion is entirely `RefreshAllFeedsWorker` → `FeedRefreshWorker` on `config/sidekiq_cron.yml`'s hourly schedule, and neither worker nor the cron schedule ever calls `Pruner`.

The practical consequence, measured directly against production:

| Query | Result |
|---|---|
| Total articles | 138,083 |
| Would delete with `keep_unread: false` (the module's own default), 7-day cutoff | 123,436 (89%) — including 121,660 **unread** articles |
| Bookmarks preserved either way | 0–6 (bookmarking is lightly used) |
| Would delete with `keep_unread: true`, 7-day cutoff | 1,776 — all already-**read**, non-bookmarked, >7 days old |
| Oldest surviving article (feed 254 webcomic archive) | `published_at` from 2012 |

This is a single-user (well, small-user) reading app where "unread" is a real, load-bearing signal — the home feed, For-You ranking, and the whole point of an RSS reader assume unread articles stick around until the user gets to them. Wiring in `Pruner` with its own default (`keep_unread: false`) would be a data-loss incident on the very first run: 121,660 articles the user hasn't read yet, gone, with no undo. That's the central risk this design has to close before anything else matters.

## Goals / Non-Goals

**Goals:**
- Make production actually run the retention sweep that already exists in code, on a recurring schedule, the same way `fix_article_links` / `generate_sudoku` / other maintenance jobs already run via `sidekiq-cron`.
- Guarantee, structurally, that the automated job can never delete an unread or bookmarked article — not by convention or a hopeful default, but by the worker's own hardcoded behavior.
- Make the first production run visible and reviewed by the user before the unattended cron entry goes live, since this is a hard DELETE against a 138K-row table that's never been swept.

**Non-Goals:**
- Solving the unread backlog (136,057 of 138,083 articles). That's `keep_unread`'s entire purpose — those articles are *supposed* to survive. If storage growth from the unread backlog becomes a problem later, that's a separate, explicit product decision (e.g. a hard age cap regardless of read state, or per-topic limits) — not something to fold into "wire up the retention that already exists."
- Changing `Pruner`'s core logic, `RETENTION_DAYS` default, or the CLI script's behavior (`scripts/refresh_feeds.rb` / `make prune` keep their existing opt-in `PRUNE_KEEP_UNREAD` semantics — a human running a CLI command can make an informed one-off choice; this change only concerns the unattended production path).
- Backfilling/fixing the specific old data already in production (e.g. feed 254's 2012-dated webcomic archive) beyond what the new recurring sweep naturally does going forward. Not manually curating old rows.

## Decisions

1. **New `PruneArticlesWorker`, mirroring `FixArticleLinksWorker`'s pattern** (`app/workers/fix_article_links_worker.rb`): a plain Sidekiq worker, `sidekiq_options queue: :default, retry: 2`, one `perform` that calls into the existing module and logs a structured result. No new abstraction — this is the same shape as three other maintenance jobs already in the codebase.
   - *Alternative considered*: call `Pruner.prune_old` directly from `RefreshAllFeedsWorker` (piggyback on the existing hourly job, matching `scripts/refresh_feeds.rb`'s own "prune after every refresh" pattern). Rejected — pruning doesn't need to run hourly, and coupling it to the feed-fan-out worker makes that worker's one job (enqueue `FeedRefreshWorker` per feed) do two unrelated things. A dedicated daily worker matches how `fix_article_links` and `generate_sudoku` are already modeled.

2. **The worker hardcodes `keep_unread: true`** rather than reading `PRUNE_KEEP_UNREAD` with `Pruner.prune_old`'s own false-by-default semantics. This intentionally diverges from the CLI script's opt-in default. Rationale: the CLI path is run by a human who sees the printed `Deleted: N` / `Kept (unread, past cutoff): N` summary before it becomes habit; the cron path runs unattended every night with nobody watching. An unattended job needs the safe behavior to be the default, not something that silently does the dangerous thing unless an env var happens to be set correctly in `.env`. `RETENTION_DAYS` stays configurable via env (defaults to `Pruner::DEFAULT_RETENTION_DAYS` = 7) since the measured blast radius at that default with `keep_unread: true` is small (1,776 rows, zero bookmarks) and matches every other place in the codebase that already assumes a 7-day window (the `/admin` dashboard's "Activity (last 7 days)" chart already uses this constant).
   - *Alternative considered*: make `keep_unread` env-configurable for the worker too, defaulting to `true`. Considered but rejected for now — it adds a knob whose only "wrong" value is actively dangerous (138K-row unread deletion), so hardcoding the safe behavior removes an entire footgun for a knob nobody has asked to turn. If there's ever a real need to prune unread articles, that should be its own explicit, reviewed decision — not a flag flip.

3. **Schedule placement**: `05:00 UTC`, after `fix_article_links` (`04:45 UTC`) and clear of the `01:30`/`04:00`-ish nightly cluster (sudoku 01:00, trivia 01:30). Mirrors the existing convention in `config/sidekiq_cron.yml` of spacing daily jobs ~15+ minutes apart to avoid contention, and running maintenance sweeps in the Droplet's quiet overnight window.

4. **`RETENTION_DAYS` / `PRUNE_KEEP_UNREAD` added to `docker-compose.yml`'s `sidekiq` service environment**, even though the worker hardcodes `keep_unread: true` (so `PRUNE_KEEP_UNREAD` from the CLI's semantics is actually irrelevant to the worker — the worker will document this clearly in its own comment). `RETENTION_DAYS` is added so the retention window is an operator-visible, documented knob (like `HEALTH_FRESH_HOURS` / `HEALTH_DEAD_MAX` in `docs/alerting.md`) rather than a buried Ruby constant.

5. **First production run happens manually, reviewed, before the cron entry is enabled.** Given the blast-radius numbers above are current-as-of-investigation and could drift before this ships, the implementation re-verifies against live production data immediately before flipping this on, and the first actual prune run is triggered manually (e.g. via a one-off `docker compose exec sidekiq bundle exec ruby -e '...'` or by deploying the worker first and triggering it once via the Sidekiq UI "force run" pattern already used for `sudoku`/`trivia`/`index_sync`) so the user sees the real `Deleted: N` count before it becomes a recurring unattended job.

## Risks / Trade-offs

- [`Pruner.prune_old` is a hard DELETE with no undo/soft-delete] → Mitigated structurally: `keep_unread: true` hardcoded in the worker makes the dangerous case (deleting unread articles) unreachable via the automated path regardless of env misconfiguration. Bookmarks are already unconditionally preserved by `Pruner`'s own logic (not something this change touches).
- [Blast-radius numbers (1,776 rows) were measured at proposal time and could be stale by the time this ships] → Task list re-confirms against live production data immediately before enabling, and the first run is manual/visible rather than silently absorbed into the cron schedule.
- [Read-but-unbookmarked articles the user might still want (e.g. to re-read, share, or reference) get permanently deleted after 7 days] → This is the pre-existing, already-documented intent of `Pruner` (`DEFAULT_RETENTION_DAYS = 7`, described in the module's own comments as "we don't need them for the reading flow once the user has triaged them") — this change enforces an existing documented policy, it doesn't invent a new one.
- [Adding a new daily DELETE-heavy job to a 138K-row (and growing-but-now-bounded-by-read-articles) table could be slow on the Droplet's `db-s-1vcpu-1gb` Postgres tier] → The steady-state deletion count after the first sweep will be small (new reads accumulate slowly for a single/small-user app); only the first run touches meaningfully more rows (1,776), which is not a heavy operation. No index changes anticipated, but the implementation checks `EXPLAIN` on the delete query against production-scale data if this turns out to matter.

## Migration Plan

No schema changes. Deploy via the project's standard `make release-patch` pipeline. The cron entry itself is data-safe to roll back (removing it from `config/sidekiq_cron.yml` and redeploying simply stops future runs; already-deleted articles are not recoverable, which is why the manual-first-run step exists as the real safety gate, not the rollback path). Sequencing: ship the worker + cron entry together, but the manual verification run happens as its own reviewed step before/alongside enabling — see tasks.md.

## Open Questions

- None blocking. If the user wants `keep_unread` to ever be a real, safely-defaulted knob (rather than hardcoded `true`), that's a follow-up, not a blocker for this change.
