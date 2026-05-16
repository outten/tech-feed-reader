# Deployment Planning

Analysis + recommendations for taking the app from local-only (SQLite,
single-machine) to publicly accessible on the internet. Cost-aware
because there's no monetization model yet.

This is a planning doc, not a runbook. It captures the trade-offs and
the chosen direction so we don't re-litigate them later.

---

## TL;DR

- **Database:** PostgreSQL (not MySQL). Keep integer IDs — don't migrate
  to UUIDs.
- **Hosting:** Fly.io for the app + Neon for Postgres + Upstash for
  Redis. Realistic monthly cost: **$0–15** at hobby scale. Avoid the
  big three (AWS / GCP / Azure) — they're priced for funded startups
  and easy to overspend on by accident.
- **Critical pre-deploy blocker:** per-user LLM rate limiting. Right
  now any signed-in user can drain the Anthropic API key via /triage,
  /chat, /article/:uid/summarize/llm, and /digests/:id/summarize. The
  $200/mo Max subscription does **not** cover those — they're billed
  separately as pay-as-you-go.

---

## Database

### Why Postgres, not MySQL

Both work, but Postgres is the right pick for this app specifically:

- **Full-text search.** We currently use SQLite FTS5 (search box on
  /articles, semantic-ish ranking). Postgres has `tsvector` /
  `tsquery` which is a clean equivalent. MySQL's FULLTEXT is weaker
  and the migration would be harder.
- **JSON.** Postgres `jsonb` is properly indexable and queryable.
  MySQL's JSON support has improved but is still second-class.
- **Ruby ecosystem default.** Sinatra + Postgres is the well-trodden
  path. More managed offerings (Neon, Supabase, RDS, CloudSQL) treat
  Postgres as the first-class option.
- **Concurrency.** SQLite's writer-serialization will bite as soon as
  more than one user is writing simultaneously. Postgres MVCC handles
  this natively.

### Migration scope

Every `Database.execute` raw-SQL call needs an audit for SQLite-isms:

- `INSERT OR IGNORE` / `INSERT OR REPLACE` → Postgres `ON CONFLICT … DO NOTHING/UPDATE`
- `||` string concatenation works in both, but check for SQLite-only datetime functions (`datetime('now')`, `strftime`)
- `AUTOINCREMENT` → Postgres `SERIAL` / `BIGSERIAL` / `GENERATED ALWAYS AS IDENTITY`
- WAL mode + busy-timeout pragmas are SQLite-only — drop them
- FTS5 virtual tables → rebuild as `tsvector` columns + GIN indexes + triggers (this is the biggest single piece of work)
- `Database.migrate!` runner needs Postgres-aware DDL

Spec suite catches most behavioral regressions if we run it against
both backends during the transition — keep SQLite for fast local
tests, run a Postgres CI job in parallel.

### IDs: keep integers

The question was integer vs UUID/GUID. Recommendation: **stay on
integers** for internal IDs.

- Public URLs already use `uid` slugs (e.g. `/article/:uid`) — that's
  the right pattern for non-enumerable public references, and it's
  already in place.
- UUIDs cost 2× storage per ID, slower B-tree inserts, slightly slower
  joins. Worth it only if you have a concrete need: client-generated
  IDs, sharding, federation, or refusing to leak ordinal info on
  public endpoints. None applies here.
- Migration cost is non-trivial (every FK column, every spec fixture).

If a specific entity ever needs to be both publicly-addressable and
non-enumerable, give it a slug column like articles already have.

---

## Pre-Deployment Blockers

Listed in priority order. The first one is a hard gate.

### 1. LLM cost containment (BLOCKER)

The app has four routes that spend Anthropic API tokens on user action:

- `POST /triage` — Claude Sonnet 4.6 classification, ~$0.02–0.04 per call, 10–30s
- `POST /article/:uid/summarize/llm` — per-article Claude summary, 5–15s
- `POST /digests/:id/summarize` — full-digest Claude summary, 5–15s
- `POST /chat` (chat widget) — interactive, per-message

These bill against the Anthropic API key in `.credentials`, **not** the
$200/mo Claude Max subscription. With open signup and no rate limits,
a malicious or buggy client could drain the key in minutes.

Minimum gates before public deploy:

- Per-user daily token quota (track in DB, enforce in route)
- Global circuit-breaker: if API spend in last hour exceeds $X, refuse
  new LLM requests until reset
- Feature flag to disable LLM features entirely without redeploying
- Consider gating LLM features behind a "trusted" user flag granted
  manually or via invite code

### 2. WebAuthn domain binding

Passkey credentials are scoped to `WEBAUTHN_RP_ID`. When we move from
localhost to a real domain, all existing passkeys become invalid for
that domain.

Options:
- Greenfield: drop local users, start fresh on production
- Migration: give existing users a one-time recovery-code sign-in
  flow, then re-register a passkey under the new RP ID

`WEBAUTHN_RP_ID` and `WEBAUTHN_ORIGIN` env vars need to be set to
production values before any user registers.

### 3. Operational basics

- **Secrets management.** Currently `.credentials` + `.env` files.
  Need a real secrets provider (Fly.io secrets, Render env vars,
  Doppler, 1Password CLI, etc.) — never bake into images.
- **HTTPS.** Required for WebAuthn (passkeys don't work over plain
  HTTP). Cloudflare in front, or Caddy/Traefik with Let's Encrypt, or
  the platform's built-in TLS termination.
- **Backups.** Daily Postgres logical backup to S3-compatible storage
  (Backblaze B2, R2, Tigris). Test the restore.
- **Rate limiting** at the HTTP layer (Cloudflare WAF or `rack-attack`)
  for sign-up, sign-in, and any unauthenticated endpoint.
- **Privacy policy + ToS.** Legal angle once it's public. Even a
  one-paragraph statement is better than nothing.
- **Session secret** must be a strong random value set via env, never
  the dev default.

### 4. Nice-to-haves (not blockers)

- CDN in front of `public/` (Cloudflare is free and handles this)
- Structured logging shipped somewhere queryable (Axiom, BetterStack,
  or just S3 + Athena)
- Uptime monitoring (`/health` endpoint already exists — point UptimeRobot at it)
- Per-user feed-refresh quotas (cheap, but unbounded if abused)

---

## Hosting Comparison

Filtered through "cost-aware, no monetization, single developer."

### Why not AWS / GCP / Azure

All three are priced for credit-funded startups. They'll happily charge
you $40/mo for an idle setup, and the failure mode is a $400 surprise
bill from a forgotten NAT gateway, an orphaned EBS volume, or
egress-fee surprises. Worth it when you have a finance team or a
revenue model — not now.

Exception: if you have AWS credits sitting unused, the math changes.

### Options

| Tier | Stack | Monthly | Trade |
|---|---|---|---|
| Cheapest serious | Hetzner CX22 (~$4.50) running Docker Compose for app + Postgres + Redis; Cloudflare in front; Caddy for TLS | **~$5** | You own ops: OS patches, backup scripts, restart-on-reboot |
| **Recommended** | Fly.io for the Sinatra app + Sidekiq worker process; Neon for Postgres (serverless, free tier <10GB, scales to zero); Upstash for Redis (Sidekiq queue, free tier) | **$0–15** | Managed everything, no ops, low ceiling on surprise costs |
| Predictable + managed | DigitalOcean App Platform for app; DO Managed Postgres; DO Managed Redis | **~$20** | One vendor, one bill, simple mental model |
| All-Heroku-like | Render Web Service + Render Postgres + Render Redis | **~$15–25** | Familiar Heroku-style UX, less generous free tier than Fly |

### Recommendation: Fly.io + Neon + Upstash

- **Fly.io** runs the Sinatra app + Sidekiq worker as separate processes
  in a single `fly.toml`. Free allowance covers small VMs; pay only as
  you scale. Deploys via `fly deploy` from a Dockerfile.
- **Neon** for Postgres. Serverless model: scales to zero when idle,
  free tier covers ~10GB and 100 hours/mo of active compute. No need
  for an always-on DB instance.
- **Upstash** for Redis (Sidekiq queue + rate limit counters). Free
  tier covers low-volume use; per-request billing keeps surprise
  costs near zero.

Total realistic monthly cost at hobby traffic: $0–10. Worst case if
something goes viral: $15–30 with auto-scale, still bounded.

### Fallback: Hetzner VPS

If the managed free tiers shrink (Fly recently reduced theirs), drop
to a Hetzner CX22 ($4.50/mo) with Docker Compose running app +
Postgres + Redis + Caddy. Total fixed cost ~$5/mo, no surprises,
slightly more ops burden.

---

## Pre-Deploy Checklist (for when we start)

- [ ] Port `Database` layer to Postgres; spec suite green against both backends
- [ ] Port FTS5 → tsvector with proper triggers + GIN index
- [ ] Audit raw SQL for SQLite-isms
- [ ] Add `LlmQuota` (per-user daily token cap) + circuit-breaker middleware
- [ ] Feature flag to disable LLM routes server-wide
- [ ] `WEBAUTHN_RP_ID` / `WEBAUTHN_ORIGIN` set from env, not hardcoded
- [ ] All secrets moved from `.credentials` to platform env vars
- [ ] Daily Postgres backup to S3-compatible storage; restore tested
- [ ] `rack-attack` (or equivalent) on sign-up + sign-in
- [ ] HTTPS enforced (HSTS header)
- [ ] Privacy policy + ToS published
- [ ] Cloudflare in front for CDN + WAF + DDoS
- [ ] Uptime monitor pointed at `/health`

---

## Open Questions

- **Invite-only vs open signup?** Drastically changes the LLM-cost
  blast radius. Invite-only buys time before the rate-limit work is
  bulletproof.
- **Multi-tenant strain.** The app is multi-user but every feature
  has been exercised primarily with one user. Worth a load-test
  before opening up.
- **Image storage.** Currently the page-background pool fetches from
  Picsum at runtime. No user-uploaded images today. If we ever add
  them, need S3/R2/B2 plus a sanitization pipeline.
- **Email.** Currently no email anywhere (passkey-only auth helps).
  Some features eventually want it (digest delivery? account recovery
  outside the recovery-codes flow?). Worth a placeholder decision.
