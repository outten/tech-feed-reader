# Capacity / load-test assessment — 2026-06

Pre-launch capacity check. **Outcome: documented, no changes made** (capacity
judged acceptable for a steady launch; levers recorded for when traffic warrants
them).

## Method

- Local app at production scale (32k-article `tfr_dev`, `RACK_ENV=test` to bypass
  auth), same concurrency model as prod: **Puma 5 threads, `DB_POOL=5`**.
- `ab` ramp at concurrency 1 / 5 / 10 / 20 against the home, list, and article
  routes.
- The managed Postgres was **not** load-tested directly — it sits near its
  connection cap (see below), so opening test connections risks
  "too many connections" for live users. Instead, representative heavy queries
  were timed against it with a single read-only connection to isolate the
  DB-vs-CPU question.

## Results

| Path | c=1 p50 | c=20 p50 | Throughput ceiling | Verdict |
|------|--------:|---------:|-------------------:|---------|
| `/article/:uid` | 2 ms | 37 ms | 500+ req/s | ✅ Excellent — scales flat |
| `/articles` | ~64 ms | — | high | ✅ Fine |
| `/` (home) | 205 ms | 1365 ms | **~14 req/s / process** | ⚠️ The ceiling |

0 failed requests throughout. Article/reading paths are a non-issue — the
v1.1.0/v1.1.1 deferred-work optimizations (async Read-next + Related) paid off.

The **home page is the binding constraint**: throughput flatlines at ~14 req/s
past 5 concurrent requests, and latency then grows linearly with concurrency —
classic thread-pool queueing at the 5-thread limit.

## Root cause: CPU/Ruby-bound, not DB-bound

The managed PG answers the home page's heavy queries in **2–3 ms** — the same as
local (the 32k-row corpus fits in its cache). So the home page's ~205 ms is
**Ruby work**, not database:

- `Recommendation::ForYou.score_window` runs **twice** per home load — once for
  the main feed, once inside `load_whats_on_today!` (`app/main.rb` ~:658).
- `load_whats_on_today!` (`app/main.rb` :640) is **uncached** — sports-match
  lookups + the For-You re-run + video/audio/reading partitioning happen every
  load.
- ERB rendering of the assembled home page.

The 5-thread GVL caps a single process at ~14 home-loads/s regardless of the
fast DB.

## Connection state (noteworthy)

Prod managed PG (`db-s-1vcpu-1gb`): `max_connections = 25`, `reserved = 3`,
**~22 used at idle**. The app self-caps at ~12 (web `DB_POOL` 5 + ambient,
Sidekiq 5 + ambient), so app load will **not** exhaust it — but there is **zero
headroom** to add a Puma worker or raise `DB_POOL`, and a connection leak or a
DO-system spike could trip "too many connections."

## Capacity estimate

~14 home-loads/sec/process ≈ **840/min ≈ 50k/hour**. Adequate for a steady
launch; **would queue under a spike** (Show HN / Product Hunt front page →
hundreds concurrent).

## Levers (by bang-for-buck) — recorded, not applied

1. **Cache the home-page Ruby work** — memoize `load_whats_on_today!` (short TTL)
   and avoid the duplicate `score_window`. *Code-only, no infra, no cost.*
   Estimated home p50 ~205 ms → ~60 ms ≈ **2–3× throughput**. Best first move.
2. **Bump PG tier** → `db-s-1vcpu-2gb` (~47 connections, +~$15/mo). Fixes the
   22/25 near-cap risk **and** unlocks lever 3. (`terraform/database.tf`.)
3. **Puma cluster** — 2–3 workers on the 4-vCPU droplet multiplies home
   throughput (it's CPU-bound, so more processes help). **Requires lever 2 first**
   (each worker needs its own `DB_POOL`). See STUFF #100.

Recommended order when traffic warrants: **1 → 2 → 3**. Lever 1 is worth doing
regardless; lever 2 is cheap connection-safety insurance before a public launch.
