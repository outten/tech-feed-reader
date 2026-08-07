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
- ~~Solving the unread backlog~~ — **superseded by the Revision section below.** Originally scoped out as a separate decision requiring its own review; that review happened (real growth-rate + DB-size data gathered post-ship) and concluded a bounded 30-day window is the right call. This is that explicit, reviewed decision, not scope creep.
- Changing `Pruner`'s core logic, `RETENTION_DAYS` default, or the CLI script's behavior (`scripts/refresh_feeds.rb` / `make prune` keep their existing opt-in `PRUNE_KEEP_UNREAD` semantics — a human running a CLI command can make an informed one-off choice; this change only concerns the unattended production path).
- Backfilling/fixing the specific old data already in production (e.g. feed 254's 2012-dated webcomic archive) beyond what the new recurring sweep naturally does going forward. Not manually curating old rows.

## Decisions

1. **New `PruneArticlesWorker`, mirroring `FixArticleLinksWorker`'s pattern** (`app/workers/fix_article_links_worker.rb`): a plain Sidekiq worker, `sidekiq_options queue: :default, retry: 2`, one `perform` that calls into the existing module and logs a structured result. No new abstraction — this is the same shape as three other maintenance jobs already in the codebase.
   - *Alternative considered*: call `Pruner.prune_old` directly from `RefreshAllFeedsWorker` (piggyback on the existing hourly job, matching `scripts/refresh_feeds.rb`'s own "prune after every refresh" pattern). Rejected — pruning doesn't need to run hourly, and coupling it to the feed-fan-out worker makes that worker's one job (enqueue `FeedRefreshWorker` per feed) do two unrelated things. A dedicated daily worker matches how `fix_article_links` and `generate_sudoku` are already modeled.

2. ~~**The worker hardcodes `keep_unread: true`**~~ — **superseded by Decision 2 (revised), below.** This was the correct call for the *first* production run against an unaudited 138K-row backlog. It's not the correct call forever — see the revision for what changed once the growth rate was actually measured.
   - *Alternative considered*: make `keep_unread` env-configurable for the worker too, defaulting to `true`. Considered but rejected for now — it adds a knob whose only "wrong" value is actively dangerous (138K-row unread deletion), so hardcoding the safe behavior removes an entire footgun for a knob nobody has asked to turn. If there's ever a real need to prune unread articles, that should be its own explicit, reviewed decision — not a flag flip.

## Revision (post-ship): bounded retention, not unread-forever

Shipped first with `keep_unread: true` hardcoded — deliberately, per Decision 2 above, because the first-ever run against a never-pruned 138K-row table needed the safe default while the real growth rate was unknown. That's exactly what it was for: it let the actual numbers come in safely instead of guessing.

**What the real numbers showed** (checked against live production, ~1 week after the initial ship):
- Ingestion averages **~2,000 articles/day** (weekday ~2,500, weekend ~1,100) — not the ~20,000/day back-of-envelope figure that prompted this review. The 138K *total* corpus reflects 81+ days of accumulation, not a rolling window.
- The `articles` table is **1,469 MB**; the whole database **1,566 MB**, on a **10,240 MiB (10 GiB)** managed-Postgres allocation (`db-s-1vcpu-1gb`, `terraform/database.tf`) shared with a second app ("mapper," negligible usage — 9.8 MB). ~15% used today.
- At ~2,000/day with `keep_unread: true` (i.e., unbounded), the `articles` table alone projects to **~9 GB in a year** — not an emergency, but a real, foreseeable capacity/cost event, not "growing out of hand" in the alarming sense but not nothing either.

**Two scenarios checked before deciding** (both against live data):

| | keep_unread | retention_days | would_delete (first run) | steady state |
|---|---|---|---|---|
| A (rejected) | `true` | 30 | **0** | unread backlog still grows ~2,000/day, unbounded — doesn't address the actual problem |
| B (chosen) | `false` | 30 | **74,892** (all currently-unread) | bounded to ~30 days of ingestion, ≈ 60,000 articles steady-state |

Scenario A is a trap worth naming explicitly: raising `retention_days` alone does nothing while `keep_unread: true`, since that flag exempts unread articles from the window entirely, regardless of its size. The number that actually matters is the `keep_unread` flag, not the day count, for bounding growth. Both have to change together.

**Decision 2 (revised): `keep_unread: false`, `RETENTION_DAYS: 30`.** Not a reversion to the original dangerous default (7-day window) — a distinct, informed choice. 30 days (vs. 7) was chosen specifically to give real breathing room for "catch up on the weekend" / "got busy for a couple weeks" reading patterns, while still bounding the backlog to a predictable, roughly-constant size rather than letting it grow forever. Bookmarks remain the one unconditional exemption — that invariant doesn't change.
   - *Alternative considered*: two-tier retention (short window for read articles, longer window for unread) or count-based capping (keep newest N unread) instead of a single unified window. Both remain reasonable future refinements if 30 days turns out too aggressive or too loose in practice, but a single `RETENTION_DAYS` matches `Pruner`'s existing single-window design and is simplest to reason about for a first cut at "bounded" — no need to build more mechanism than the decision currently calls for.
   - *Alternative considered*: leave `keep_unread: true` and instead buy more disk when needed (~$0.215/GiB/mo within the current tier, or $30/mo for the next tier up). Rejected as the sole fix — it defers the question rather than answering it; disk headroom doesn't cap growth, it just moves the ceiling further out. (Bumping the tier remains a reasonable *additional* lever later if 60K articles' worth of storage still needs more room than expected — not mutually exclusive with bounding growth.)

### Copy / documentation that needs updating alongside the code change

This model change touches more than the `keep_unread` argument — several places describe the *old* "unread is exempt forever" model in prose and need to change to match:

- **`app/workers/prune_articles_worker.rb`** — the inline comment currently reads "Hardcoded true, not env-driven... do not make this configurable without re-reading design.md," justified by the 89%/121K-unread-deletion danger. Needs a full rewrite: explain the *new* reasoning (30-day bounded window, chosen after the real growth rate was measured), not just flip the boolean silently. A future reader shouldn't be able to tell this was ever `true` without git-blaming it, unless the comment says so.
- **`app/pruner.rb`** — `DEFAULT_RETENTION_DAYS = 7` should become `30` (single source of truth already reused by the dashboard and the CLI script — see below). The module's top comment ("we don't need them for the reading flow once the user has triaged them") described *read* articles specifically; worth a pass to confirm it still reads correctly once unread articles are in scope for the first time.
- **`app/main.rb`'s `/admin/dashboard` route** (`@activity_window = Pruner.effective_retention_days`) and **`views/dashboard.erb`** ("Activity (last N days)" heading) — a side effect, not a bug: the dashboard chart window will change from 7 to 30 days once `DEFAULT_RETENTION_DAYS` changes, which is *correct* now that the label actually reflects enforced policy. Worth a quick look to confirm the chart still reads sensibly at 30 days (`ArticlesStore.daily_counts(user_id, days: @activity_window)`).
- **`.env.example`** — the `RETENTION_DAYS` comment block currently says "Unset → 7 (Pruner::DEFAULT_RETENTION_DAYS)"; update to 30. Consider whether `PRUNE_KEEP_UNREAD` needs any mention here too, given the worker no longer reads it (it's still relevant to the CLI script's own default, which is unaffected by this change).
- **`config/sidekiq_cron.yml`**'s `prune_articles` description — currently says "delete read, non-bookmarked articles older than RETENTION_DAYS... Unread and bookmarked articles are never deleted." The unread half of that claim becomes false; rewrite to describe the 30-day bounded model.
- **`STUFF.md` #114** — not yet marked Shipped (still open, tasks.md 5.3 pending). Its eventual Shipped writeup should describe the model actually deployed (bounded 30-day retention), not the interim safe-first version, with both the interim (1,756 deleted, keep_unread:true) and final (74,892 deleted, keep_unread:false, 30-day) numbers as a two-step story — it's a more honest record of how the decision was actually reached than only documenting the final state.
- **This change's own `proposal.md`, `specs/article-retention-enforcement/spec.md`** — already updated as part of this revision (strikethrough + pointers, not silently rewritten, so the decision history stays legible).

3. **Schedule placement**: `05:00 UTC`, after `fix_article_links` (`04:45 UTC`) and clear of the `01:30`/`04:00`-ish nightly cluster (sudoku 01:00, trivia 01:30). Mirrors the existing convention in `config/sidekiq_cron.yml` of spacing daily jobs ~15+ minutes apart to avoid contention, and running maintenance sweeps in the Droplet's quiet overnight window.

4. **`RETENTION_DAYS` / `PRUNE_KEEP_UNREAD` added to `docker-compose.yml`'s `sidekiq` service environment**, even though the worker hardcodes `keep_unread: true` (so `PRUNE_KEEP_UNREAD` from the CLI's semantics is actually irrelevant to the worker — the worker will document this clearly in its own comment). `RETENTION_DAYS` is added so the retention window is an operator-visible, documented knob (like `HEALTH_FRESH_HOURS` / `HEALTH_DEAD_MAX` in `docs/alerting.md`) rather than a buried Ruby constant.

5. **First production run happens manually, reviewed, before the cron entry is enabled.** Given the blast-radius numbers above are current-as-of-investigation and could drift before this ships, the implementation re-verifies against live production data immediately before flipping this on, and the first actual prune run is triggered manually (e.g. via a one-off `docker compose exec sidekiq bundle exec ruby -e '...'` or by deploying the worker first and triggering it once via the Sidekiq UI "force run" pattern already used for `sudoku`/`trivia`/`index_sync`) so the user sees the real `Deleted: N` count before it becomes a recurring unattended job.

## Risks / Trade-offs

- [`Pruner.prune_old` is a hard DELETE with no undo/soft-delete] → For the *unread* case specifically (new as of the revision): a 30-day window is generous enough to cover normal "got busy" gaps, and bookmarking remains the explicit, always-available escape hatch for anything the user knows they want to keep past that window — worth making sure that affordance is easy to reach in the UI, since it now carries more weight than before.
- [Blast-radius numbers were measured at proposal/revision time and could be stale by the time this ships] → Task list re-confirms against live production data immediately before enabling, and the first run under the new settings is manual/visible rather than silently absorbed into the cron schedule (same pattern as the original ship).
- [An article the user genuinely wanted to get back to, but hadn't marked read or bookmarked within 30 days, is now permanently deleted — a real behavior change from "read whenever" to "read within a month"] → This is the deliberate trade the Revision makes, chosen with real usage/growth data in hand rather than guessed. Bookmarking is the mitigation; nothing else is being added, since a second safety net (soft-delete, trash/undo) is more mechanism than the current decision calls for.
- [Adding a new daily DELETE-heavy job to a growing table could be slow on the Droplet's `db-s-1vcpu-1gb` Postgres tier] → Steady-state deletion count settles to roughly the daily ingestion rate (~2,000/day) once the 30-day window is full, which is a small, fast delete. Only the first run under the new settings touches meaningfully more rows (~74,892) — re-verify this is still comfortable before enabling, same as the original ship's verification step.

## Migration Plan

No schema changes. Deploy via the project's standard `make release-patch` pipeline. The cron entry itself is data-safe to roll back (removing it from `config/sidekiq_cron.yml` and redeploying simply stops future runs; already-deleted articles are not recoverable, which is why the manual-first-run step exists as the real safety gate, not the rollback path). Sequencing: ship the worker + cron entry together, but the manual verification run happens as its own reviewed step before/alongside enabling — see tasks.md.

## Open Questions

- None blocking for the revision. Whether 30 days proves too aggressive or too loose in practice is something to watch after a few weeks of the new steady state, not something resolvable in advance — the two-tier / count-based alternatives noted under Decision 2 (revised) are the natural next move if so.
