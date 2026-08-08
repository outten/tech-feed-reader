## 1. Implement the worker

- [x] 1.1 Create `app/workers/prune_articles_worker.rb`, mirroring `app/workers/fix_article_links_worker.rb`'s pattern: `sidekiq_options queue: :default, retry: 2`, `perform` calls `Pruner.prune_old(retention_days: ..., keep_unread: true)` and logs a structured `AppLogger.info('prune_articles_complete', deleted:, kept_bookmarked:, kept_unread:, cutoff:, retention_days:)`.
- [x] 1.2 Hardcode `keep_unread: true` in the worker (not env-driven) per design.md decision 2 — add a code comment explaining why, so a future edit doesn't "helpfully" make it configurable without re-reading the rationale.
- [x] 1.3 Read `retention_days` via `Pruner.effective_retention_days` (already implements the `ENV['RETENTION_DAYS']` fallback to `Pruner::DEFAULT_RETENTION_DAYS` — reused rather than duplicated, matching how `app/main.rb`'s dashboard already calls it).
- [x] 1.4 Require the new worker in `app/sidekiq_boot.rb`.

## 2. Wire the schedule

- [x] 2.1 Add a `prune_articles` entry to `config/sidekiq_cron.yml` at `05:00 UTC` (after `fix_article_links` at `04:45`), with a description matching the file's existing style.
- [x] 2.2 Add `RETENTION_DAYS` to `docker-compose.yml`'s `sidekiq` service environment (default unset, i.e. falls back to `Pruner::DEFAULT_RETENTION_DAYS` = 7 unless explicitly overridden in `.env`). Also documented in `.env.example`.

## 3. Test coverage

- [x] 3.1 Add `spec/prune_articles_worker_spec.rb`: seed a read+old article, an unread+old article, a bookmarked+old article, and a recent article; run the worker; assert only the read+old+non-bookmarked one is deleted.
- [x] 3.2 ~~Assert the worker logs `prune_articles_complete`~~ — dropped: `Pruner.prune_old` (`app/pruner.rb:81`) already logs a structured `'prune_articles'` event with the same fields; the worker doesn't duplicate it. Spec instead asserts the worker always calls `Pruner.prune_old` with `keep_unread: true`.
- [x] 3.3 Run `make test` (full suite) before pushing. **1746 examples, 0 failures.**

## 4. Verify against live production before enabling

- [x] 4.1 Re-run the blast-radius query from design.md against current production data (numbers may have drifted since proposal time — total article count, would-delete count with `keep_unread: true`) and confirm it's still small and touches zero bookmarks. **Re-confirmed**: 138,142 total articles (up from 138,083 at proposal time); with `keep_unread: false` would delete 123,517 (121,741 unread) — the danger case the worker's hardcoded `keep_unread: true` avoids entirely; actual worker behavior deletes **1,776** read/non-bookmarked articles; 0 bookmarks touched.
- [x] 4.2 Deploy the worker code (via the normal `make release-patch` pipeline) WITHOUT the cron entry enabled yet, or with the cron entry present but triggered manually first — confirm with the user which approach they prefer. **Shipped v1.1.27 with the cron entry present but triggered manually first.**
- [x] 4.3 Trigger the first run manually (e.g. via the Sidekiq UI "force run" pattern already used for sudoku/trivia/index_sync, or a one-off `docker compose exec sidekiq` invocation) and show the user the actual `Deleted: N` / `Kept (unread): N` result before the recurring cron entry is live. **Deleted=1,756, kept_bookmarked=6, kept_unread=121,768.**
- [x] 4.4 Only after the user reviews the first-run result, confirm the cron entry stays enabled for subsequent nightly runs (no further action needed if it's already in the deployed `sidekiq_cron.yml` — this step is the explicit go/no-go checkpoint, not a code change). **User reviewed and approved; cron entry left enabled.**

## 5. Ship (initial, safe version)

- [x] 5.1 Deploy via `make release-patch` (after explicit go-ahead) — never a manual `docker buildx`/`ssh` deploy. **v1.1.27.**
- [x] 5.2 Monitor the next scheduled `05:00 UTC` production run after deploy and confirm the logged result matches expectations (no unread/bookmarked articles deleted). **Superseded before the first scheduled run — see task group 6: the user reviewed the real growth-rate data the same day and decided to revise the model before the cron entry ever fired unattended.**
- [ ] 5.3 ~~Update STUFF.md #114 with a Shipped. statement~~ — deferred to task group 6, so the writeup captures the full two-step decision (safe-first, then revised) rather than a snapshot that's immediately out of date.

## 6. Revision — bounded retention (`keep_unread: false`, `RETENTION_DAYS: 30`)

Captured during `/openspec-explore` after reviewing real production growth data (~2,000 articles/day, `articles` table 1.5 GB of a 10 GiB shared allocation). See proposal.md's "Revision" section and design.md's "Decision 2 (revised)" for the full reasoning. Not yet implemented — explore mode doesn't write code.

- [x] 6.1 In `app/workers/prune_articles_worker.rb`, flip `keep_unread: true` → `keep_unread: false`, and rewrite the inline comment to explain the new reasoning (bounded 30-day window, chosen after real growth-rate data was reviewed) rather than leaving stale text about why `true` was hardcoded.
- [x] 6.2 In `app/pruner.rb`, change `DEFAULT_RETENTION_DAYS` from `7` to `30`.
- [x] 6.3 Update `config/sidekiq_cron.yml`'s `prune_articles` description — it currently claims "Unread and bookmarked articles are never deleted," which becomes false for the unread half.
- [x] 6.4 Update `.env.example`'s `RETENTION_DAYS` comment (currently says "Unset → 7"). Also found and fixed three more stale "default 7" references not caught during design: `views/privacy.erb` (**user-facing** privacy policy copy), `Makefile`'s `prune` target comment, `scripts/prune_articles.rb` and `scripts/refresh_feeds.rb` header comments.
- [x] 6.5 Confirm whether the `/admin` dashboard's "Activity (last N days)" chart still reads sensibly at 30 days — confirmed fine: it's a Chart.js line chart with no hardcoded column count, and `ArticlesStore.daily_counts`'s own default is already `days: 30`, so this actually converges two previously-different defaults into one.
- [x] 6.6 Update specs: `spec/pruner_spec.rb` had six cases using `days_ago: 30` as the "old" fixture against the *default* window — now the exact boundary of a 30-day window (not past it), so all bumped to `days_ago: 45`; the hardcoded `(now - 7 * 86_400)` cutoff assertion now references `Pruner::DEFAULT_RETENTION_DAYS`. `spec/prune_articles_worker_spec.rb` updated similarly plus the `keep_unread: true` → `keep_unread: false` expectation. `spec/cosmetics_spec.rb`'s dashboard-heading test hardcoded "Activity (last 7 days)" with an explicit `not_to include('...30 days)')` guard (written to prove the dashboard used Pruner's number, not `ArticlesStore.daily_counts`'s own default-30 coincidentally) — since both are now 30, rewrote to assert against `Pruner::DEFAULT_RETENTION_DAYS` directly so it can't silently drift again.
- [x] 6.7 Re-verify the blast radius against live production data immediately before deploying (numbers from the explore session — `would_delete = 74,892` — will have drifted by the time this ships). **Re-confirmed**: 136,710 total; would_delete=74,903 (all unread, matching the explore-session estimate closely); 5 bookmarks past cutoff, 0 touched.
- [x] 6.8 Run `make test` (full suite) before pushing. **1746 examples, 0 failures.**
- [x] 6.9 Deploy via `make release-patch` (after explicit go-ahead). **v1.1.28.**
- [x] 6.10 Trigger the first run under the new settings manually (same pattern as before) and show the user the actual result before the nightly cron takes over again. **Deleted=74,934, kept_bookmarked=5. Corpus 136,710 → 61,852.**
- [x] 6.11 Update STUFF.md #114 with a **Shipped.** statement covering both steps: the initial safe-first ship (1,756 deleted, `keep_unread: true`) and the revision (bounded 30-day window, `keep_unread: false`, actual first-run count). Also swept `AGENTS.md`, `docs/ARCHITECTURE.md`, and `docs/alerting.md` for other stale copy from this and the trivia change while doing a full documentation pass.
