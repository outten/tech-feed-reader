## 1. Confirm production root cause

- [ ] 1.1 Pull the Droplet's `sidekiq` container logs (`docker compose logs sidekiq` or persisted log path) filtered for `trivia`, `NameError`, and `dead`, covering at least the last several scheduled 01:30 UTC runs.
- [ ] 1.2 Check `/admin/status` (cron panel + Sidekiq stats) and `/admin/sidekiq`'s dead set for any `GenerateTriviaWorker` entries and their exact error.
- [ ] 1.3 Confirm whether the Droplet's failure signature matches the local dev evidence (`NameError: uninitialized constant GenerateTriviaWorker`) or differs. If it differs, stop and re-scope tasks 3+ around the actual cause before proceeding.
- [ ] 1.4 Confirm whether `NTFY_URL` is set in the Droplet's `/opt/app/.env`, and if a dead-job alert for `GenerateTriviaWorker` was ever pushed/received.

## 2. Reproduce locally

- [ ] 2.1 Start two independent Sidekiq processes against the same local Redis (e.g. `make sidekiq` in one terminal, `make run-all` in another) and confirm this reproduces `NameError: uninitialized constant GenerateTriviaWorker` for a cron- or manually-enqueued `GenerateTriviaWorker` job.
- [ ] 2.2 Confirm a single, cleanly-started Sidekiq process never exhibits this failure (i.e., isolate the cause to concurrent/stale processes, not the worker code itself).

## 3. Harden dev process lifecycle

- [ ] 3.1 In `scripts/run_all.sh`, before backgrounding a new Sidekiq process, detect and kill any process matching the Sidekiq worker's exact command line (`bundle exec sidekiq -r ./app/sidekiq_boot.rb`) that isn't the one already tracked live in `tmp/pids/sidekiq.pid`, mirroring the pattern `make stop` uses for the web process on port 4567.
- [ ] 3.2 Apply the equivalent guard in `scripts/stop_all.sh` so stopping the stack always kills any matching Sidekiq process even if `tmp/pids/sidekiq.pid` is stale or missing.
- [ ] 3.3 Re-run the task 2.1 reproduction after the fix and confirm only one Sidekiq process is ever alive, and the job succeeds every time.

## 4. Confirm/close the alerting gap

- [ ] 4.1 Based on task 1.4: if `NTFY_URL` is unset on the Droplet, set it per `docs/alerting.md` and verify with the documented test push.
- [ ] 4.2 If `NTFY_URL` is already set, verify the dead-job alert actually fires end-to-end (e.g. temporarily force a job into the dead set in a safe way, or review Notifier's rate-limit/dedupe logic against the observed timeline) so silence going forward is trustworthy.

## 5. Apply production fix (only if task 1 found a differing/additional cause)

- [ ] 5.1 If task 1 surfaces a Droplet-specific cause (e.g. a leftover non-Docker Sidekiq process, or a code/config defect), implement the targeted fix here.
- [ ] 5.2 Deploy via `make release-patch` per the project's standard release process (after explicit go-ahead) — never a manual `docker buildx`/`ssh` deploy.

## 6. Verify

- [ ] 6.1 Let the `generate_trivia` cron fire naturally (or trigger via the Sidekiq UI `force: true` arg) in dev after the task 3 fix, and confirm success with no `NameError`.
- [ ] 6.2 Monitor the next scheduled 01:30 UTC production run after any deploy and confirm a quiz is generated without manual intervention.
- [ ] 6.3 Update `STUFF.md` with a **Shipped.** statement once the fix is confirmed working in production.
