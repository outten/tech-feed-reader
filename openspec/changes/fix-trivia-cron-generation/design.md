## Context

`GenerateTriviaWorker` (`app/workers/generate_trivia_worker.rb`) wraps the same `TriviaStore.ensure_today!` call that `scripts/generate_trivia.rb` invokes directly. The worker is required unconditionally at Sidekiq server boot (`app/sidekiq_boot.rb`) and enqueued daily at 01:30 UTC by `sidekiq-cron` from `config/sidekiq_cron.yml`.

Local `tmp/logs/sidekiq.log` (spanning 2026-06-06 through 2026-07-02, the last local dev session) shows the job succeeding most days but failing outright on at least two dates (2026-06-22, 2026-06-24) with:

```
NameError: uninitialized constant GenerateTriviaWorker
```

raised immediately (`elapsed=0.0`) — i.e. before `perform` ever runs, before `AppLogger` ever fires. Both failures retried twice (per `sidekiq_options retry: 2`), then landed in the dead set. Later the same day, a *different* process pid successfully ran the same job class. This pattern — same job class, same Redis, one process can't resolve the constant and another can — is the signature of more than one Sidekiq process (only one of which has the class loaded) competing for jobs on the same Redis instance, not a problem in `TriviaGenerator`/`TriviaStore` themselves (those never even get called when this fires).

In production, `docker-compose.yml` runs exactly one `sidekiq` container/replica, restarted only on deploy (`docker compose up -d --force-recreate --no-deps app sidekiq`), so the same failure mode would require either (a) a leftover non-Docker Sidekiq process from before this app's Docker migration, still connected to the same Redis, or (b) something else entirely — which is why confirming against the Droplet's actual logs is the first task, not an assumption.

In dev, `scripts/run_all.sh`'s `start_bg` guards against re-launching a service if its pid file points at a live process — but nothing prevents a second, independently-started Sidekiq (e.g. a bare `make sidekiq` in one terminal alongside `make run-all` in another, or a process that outlived a crashed/killed dev session with a stale pid file) from also connecting to the same local Redis and racing for jobs.

## Goals / Non-Goals

**Goals:**
- Confirm, from the Droplet's own logs/dead-set/cron panel, whether production hits the same `NameError` signature as dev, before writing any fix.
- Make it structurally impossible for a second/stale Sidekiq worker process to silently coexist and steal jobs in local dev.
- Make a pre-`perform` job failure (class resolution, or any other Sidekiq-level dead job) visible same-day, not just discoverable later by grepping raw logs.
- Confirm the existing dead-job ntfy alert is actually configured on the Droplet.

**Non-Goals:**
- Rewriting `TriviaGenerator`/`TriviaStore`/`GenerateTriviaWorker` business logic — nothing there is implicated by the evidence.
- Building new alerting infrastructure — `app/sidekiq_config.rb`'s `death_handler` already pages on any dead job; the gap (if any) is configuration/visibility, not missing capability.
- Changing the cron schedule or moving off `sidekiq-cron`.

## Decisions

1. **Investigate before fixing.** The only hard evidence is from local dev logs a month old; the Droplet may show a different or additional failure mode. First implementation task pulls `docker compose logs sidekiq` (or the Droplet's persisted logs) filtered for `trivia`/`NameError`/`dead`, plus `/admin/status`'s cron + Sidekiq panels. If production shows a different signature, the tasks below are adjusted before continuing — this design's fix targets the confirmed dev-reproducible cause but is deliberately sequenced so a differing prod cause is caught first.
   - *Alternative considered*: jump straight to hardening dev tooling since that's reproducible locally. Rejected — the proposal is explicitly about production too, and shipping a dev-only fix without checking prod risks solving the wrong problem there.

2. **Harden dev process lifecycle instead of changing worker code.** Since the evidence points to a stale/duplicate process rather than a code defect, the fix is process hygiene: before `scripts/run_all.sh` backgrounds a new Sidekiq process, kill any Sidekiq process matching `bundle exec sidekiq.*sidekiq_boot` that isn't the one tracked in `tmp/pids/sidekiq.pid` (mirroring the pattern `make stop` already uses to guarantee a single web process on port 4567). Apply the same guard to `scripts/stop_all.sh` so a kill always succeeds even if the pid file is stale, and to the bare `make sidekiq` target's startup path if feasible without changing its simple one-line contract.
   - *Alternative considered*: rely on Redis-side job locking (e.g. `sidekiq-unique-jobs`) to make duplicate processing safe regardless of how many workers are alive. Rejected as disproportionate — the actual problem is a process-count invariant being violated in dev tooling, not a need for distributed locking around this or any other job.

3. **Surface pre-`perform` failures without new infrastructure.** `death_handlers` in `app/sidekiq_config.rb` already fires `Notifier.push` for any dead job, keyed by class name (`dedupe_key: "jobdeath:#{job['class']}"`) — this would have already paged for a dead `GenerateTriviaWorker` job if `NTFY_URL` is set. So the task here is verification (is `NTFY_URL` actually set on the Droplet?) and, if it's confirmed the alert exists but wasn't noticed, no code change is needed — just confirming the operational assumption. If `NTFY_URL` is unset, that's the actual visibility gap and setting it (per `docs/alerting.md`) is the fix, independent of this bug's root cause.
   - *Alternative considered*: add trivia-specific alerting distinct from the generic dead-job handler. Rejected — duplicating alerting logic per-job-class is exactly the kind of speculative abstraction the generic `death_handlers` mechanism already exists to avoid.

## Risks / Trade-offs

- [Droplet logs may not show the `NameError` pattern at all, meaning production's actual cause is unconfirmed and different from dev's] → Task 1 is a hard gate: if the Droplet's failure signature differs, stop and re-scope the remaining tasks around what's actually found there rather than applying the dev-derived fix blindly.
- [Killing Sidekiq processes by pattern-match in dev tooling could kill a process the user intentionally started outside `run_all.sh`/`stop_all.sh` for manual debugging] → Match the exact command line (`bundle exec sidekiq -r ./app/sidekiq_boot.rb`) as `make stop` does for the web process, and only from within `run_all.sh`'s own startup path (i.e., only when about to start a new one anyway), not as a standalone always-on sweep.
- [`NTFY_URL` verification requires Droplet access / operator confirmation] → Frame as a checklist task the user (who has Droplet access) confirms; not blocking on Claude Code being able to SSH in autonomously.

## Migration Plan

No data migration. Deploy path: land dev-tooling changes via a normal PR/merge; no `make deploy` needed unless the Droplet-side investigation (task 1) turns up a production code/config fix, in which case that follows the existing `make release-patch` release process per project convention. Rollback is trivial (revert the shell script changes) since nothing touches persisted state.

## Open Questions

- Does the Droplet's `docker compose logs sidekiq` show the same `NameError: uninitialized constant GenerateTriviaWorker` pattern, or something else? (Resolves in task 1; determines whether tasks 2+ need re-scoping.)
- Is `NTFY_URL` currently configured on the Droplet? If yes, was a past `GenerateTriviaWorker` dead-job alert simply missed/ignored, or did the alert never fire because the job never actually reached the dead set in production (i.e., prod's failure mode is silent/non-crashing rather than a dead job)?
