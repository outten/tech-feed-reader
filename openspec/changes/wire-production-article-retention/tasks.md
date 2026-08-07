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
- [ ] 4.2 Deploy the worker code (via the normal `make release-patch` pipeline) WITHOUT the cron entry enabled yet, or with the cron entry present but triggered manually first — confirm with the user which approach they prefer.
- [ ] 4.3 Trigger the first run manually (e.g. via the Sidekiq UI "force run" pattern already used for sudoku/trivia/index_sync, or a one-off `docker compose exec sidekiq` invocation) and show the user the actual `Deleted: N` / `Kept (unread): N` result before the recurring cron entry is live.
- [ ] 4.4 Only after the user reviews the first-run result, confirm the cron entry stays enabled for subsequent nightly runs (no further action needed if it's already in the deployed `sidekiq_cron.yml` — this step is the explicit go/no-go checkpoint, not a code change).

## 5. Ship

- [ ] 5.1 Deploy via `make release-patch` (after explicit go-ahead) — never a manual `docker buildx`/`ssh` deploy.
- [ ] 5.2 Monitor the next scheduled `05:00 UTC` production run after deploy and confirm the logged result matches expectations (no unread/bookmarked articles deleted).
- [ ] 5.3 Update STUFF.md #114 with a **Shipped.** statement, including the actual first-run deletion count.
