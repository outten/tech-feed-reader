# Ops alerting

Pre-launch push alerting so the operator finds out about prod problems
*first* — before users report them. Alerts go out as phone push via
[ntfy](https://ntfy.sh) (free, no account).

## What fires an alert

| Source | Trigger | Where |
|--------|---------|-------|
| **HTTP 500** | Any unhandled exception in a web request | Sinatra `error` handler (`app/main.rb`) |
| **Dead job** | A Sidekiq job exhausts all retries and lands in the dead set | `death_handler` (`app/sidekiq_config.rb`) |
| **Health check** | DB unreachable · feed pipeline stalled (no article fetched in `HEALTH_FRESH_HOURS`) · Sidekiq dead set over `HEALTH_DEAD_MAX` | `HealthAlertWorker`, every 5 min |
| **Trivia generation skipped** | `GenerateTriviaWorker` completes without producing a quiz (unavailable, or Claude's response didn't parse into enough valid questions) | `GenerateTriviaWorker#perform` (`app/workers/generate_trivia_worker.rb`) |

This last one exists because a skipped generation isn't a crash — the Sidekiq job finishes normally, so it never reaches the dead-job path above. See `openspec/changes/fix-trivia-cron-generation` for the incident that motivated it (a low-content source feed starved the day's trivia prompt, silently, with nothing in the dead set to alert on).

All four route through `Notifier.push` (`app/notifier.rb`):

- **No-op when `NTFY_URL` is unset** — the alert is logged at `warn` instead, so
  dev / test / CI never push.
- **Rate-limited** per `dedupe_key` via Redis, so a recurring fault pings once
  (15 min for 500s/job-deaths). The health check is dedup-free but only pushes
  on a *state transition* (ok→problem, problem→ok), so a sustained outage pushes
  once, and you get a "recovered" push when it clears.
- **Never raises into the caller** — alerting runs from error paths and inside
  jobs; a wedged ntfy or Redis is swallowed + logged, never cascaded.

## Setup

1. **Pick a topic.** Choose a hard-to-guess slug (ntfy topics are public — the
   slug *is* the access control). E.g. `feeder-ops-9f3a2c`.
2. **Set the env var** in the Droplet's `.env`:
   ```
   NTFY_URL=https://ntfy.sh/feeder-ops-9f3a2c
   ```
   It's wired through to both the `app` and `sidekiq` services in
   `docker-compose.yml`.
3. **Subscribe** in the ntfy app (iOS/Android) or at `https://ntfy.sh/feeder-ops-9f3a2c`
   to the same topic.
4. **Redeploy** (`make deploy`) so both containers pick up `NTFY_URL`.
5. **Verify**: `docker compose exec app bundle exec ruby -e 'require_relative "app/notifier"; Notifier.push(title: "Feeder test", body: "hello", priority: "low")'`
   — you should get a push within a second.

### Tunables (optional)

| Var | Default | Meaning |
|-----|---------|---------|
| `HEALTH_FRESH_HOURS` | `6` | Newest `articles.fetched_at` older than this → "feed pipeline stalled" |
| `HEALTH_DEAD_MAX` | `25` | Sidekiq dead-set size over this → alert |

## Known blind spot

`HealthAlertWorker` runs *inside* Sidekiq, so it **cannot** detect a Sidekiq or
Redis outage, or the whole droplet going down — in those cases the job simply
doesn't run, and no alert fires. The error-handler and death-handler pushes have
the same dependency (they need the app process alive + Redis for dedup).

To close that gap without standing up infrastructure, pair this with an external
**dead-man's switch**: have `HealthAlertWorker` ping a free
[Healthchecks.io](https://healthchecks.io) check each run; if the pings stop,
Healthchecks alerts you from *outside* the box. That's intentionally not wired in
yet (it's a hosted dependency) — this doc records it as the next step if
outside-in uptime coverage is wanted.
