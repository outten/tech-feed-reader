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

---

# Phased Execution Plan — DigitalOcean

Locked decisions (2026-05-16):
- **Hosting:** Single DigitalOcean Droplet running Docker Compose
  (app + Redis + Caddy). SQLite v1.0 (Postgres deferred to v1.1
  per Phase 1 below). Target cost ~$17/mo.
- **Domain:** `tmoneystuff.com` registered at Namecheap. Apex stays
  free for other apps the user plans to deploy on the same zone;
  **this app serves at `feeder.tmoneystuff.com`**.
- **DNS:** DigitalOcean DNS (NS records at the registrar point at
  `ns{1,2,3}.digitalocean.com`). Terraform manages the single A
  record `feeder` → Droplet IP; the zone itself is `data`-block
  read-only so Terraform doesn't disturb the apex / other apps.
- **TLS:** Caddy on the Droplet mints a Let's Encrypt cert
  directly via HTTP-01. No CDN / WAF in front for v1; can add
  later if abuse appears.
- **Backups:** Nightly SQLite `.backup` to DigitalOcean Spaces
  with rotation (14d daily / 60d weekly / 400d monthly).

Ownership convention: **YOU** = manual steps the user does. **CLAUDE**
= code/IaC I write into the repo.

## Phase 0 — Account + credential setup (YOU, ~45 min)

These are external accounts and tokens. Nothing in the repo changes.

- [ ] **DigitalOcean account.** Sign up at https://digitalocean.com,
      add a payment method. (Optional: use a referral link for credit.)
- [ ] **DO Personal Access Token.** Dashboard → API → Generate New
      Token, scopes: `read` + `write`. Save it — Terraform needs it.
- [ ] **DO Spaces access key.** Dashboard → API → Spaces Keys → Generate.
      Save the access key + secret. Backup script needs it.
- [x] **Domain name.** `tmoneystuff.com` registered at Namecheap.
- [x] **Repoint nameservers.** At Namecheap, replaced the default
      nameservers with `ns1.digitalocean.com` / `ns2.digitalocean.com` /
      `ns3.digitalocean.com`. DNS propagation a few hours to a day.
- [ ] **Add the zone in DO control panel.** Networking → Domains →
      Add Domain → enter `tmoneystuff.com`. This is what
      Terraform's `data "digitalocean_domain" "zone"` reads — it
      will NOT create the zone for you. The apex stays alone; this
      app's A record lives at `feeder.tmoneystuff.com`.
- [ ] **Generate production secrets.** A strong random `SESSION_SECRET`
      (e.g. `ruby -rsecurerandom -e 'puts SecureRandom.hex(64)'`).
      Confirm your existing `ANTHROPIC_API_KEY` is the one you want
      production to use (or mint a new one scoped to prod).
- [ ] **SSH key.** Ensure you have an SSH keypair (`~/.ssh/id_ed25519`)
      and the public key is in DigitalOcean → Settings → Security →
      SSH Keys. Terraform will inject it into the Droplet.

When all the above is done, hand me the token values via env vars or
a local `terraform.tfvars` file (never committed) and I run Phase 2.

## Phase 1 — Codebase prep (CLAUDE) ✅ COMPLETE

Make the app deployable + safe to expose. **Done — three PRs landed:**

- [x] **LLM rate limiting** (PR #103). `LlmGuard` enforces a per-user
      24h token quota + global hourly token/cost circuit-breaker +
      `LLM_ENABLED` kill switch. `/admin/llm-quota` surfaces budgets
      and usage. All four routes (`/triage`, `/chat`, `/article/:uid/summarize/llm`,
      `/digests/:id/summarize`) wrapped.
- [x] **Dockerfile + docker-compose + Caddyfile** (PR #104). Multi-stage
      Ruby image, non-root user. Compose runs `app` + `sidekiq` + `redis`
      + `caddy` services. Caddy auto-mints Let's Encrypt cert end-to-end.
- [x] **Per-IP RateLimiter** (PR #105). In-process middleware throttling
      `/sign-in`, `/sign-up`, `/api/auth/*`, `/chat`. Returns 429 + JSON +
      `Retry-After`. Defense-in-depth on top of WebAuthn + LlmGuard.

### Confirmed already correct (no PR needed)

- **WebAuthn env-driven** — `app/auth.rb` already reads `WEBAUTHN_RP_NAME/RP_ID/ORIGIN`
  from ENV with localhost defaults.
- **Secrets env-driven** — `app/credentials.rb` calls `Dotenv.load` which
  silently no-ops when `.credentials` is missing (the production case).
  The `.dockerignore` keeps `.credentials` out of the image entirely.
- **Healthcheck** — `/health` already reports DB + Redis status. The
  Dockerfile uses it as the container healthcheck.

### Deferred to v1.1 (decision: ship 1.0 on SQLite first)

- ~~Postgres support, SQL audit, FTS5 → tsvector, dialect-aware
  migration runner, CI matrix~~. **Re-prioritised 2026-05-17 once
  v1.0 was live — moved into Phase 5 below.** The original reasoning
  (saved engineering effort funds other work) held up through Phase
  0-3; now that we're live with real signups, the user decided to do
  the migration **next** rather than build SQLite backup tooling
  that becomes throwaway when PG lands. SQLite is fine in the
  meantime (single user; data loss between now and Phase 5 cutover
  is explicitly accepted).

## Phase 2 — Terraform (CLAUDE) ✅ SCAFFOLDED

`terraform/` directory checked in. One-command apply: `terraform apply`
after `terraform.tfvars` is populated.

- [x] **`providers.tf`** — `digitalocean` provider only (pinned).
      Cloudflare was dropped when the DNS authority moved to DO.
- [x] **`variables.tf`** — `do_token`, `do_spaces_*`, `domain` (apex,
      e.g. `tmoneystuff.com`), `app_subdomain` (default `feeder`),
      `region` (default `nyc3`), `droplet_size` (default
      `s-1vcpu-2gb`, $12/mo), `ssh_key_fingerprint`,
      `ssh_public_key_path` (defaults to `~/.ssh/id_ed25519.pub`),
      `allowed_ssh_cidrs`, `backups_bucket_name`.
- [x] **`terraform.tfvars.example`** — committed template; real
      `terraform.tfvars` is gitignored.
- [x] **`droplet.tf`** — Ubuntu 24.04 droplet, cloud-init bootstrap:
      installs Docker + compose plugin, creates `deploy` user with
      SSH key (no password), enables unattended-upgrades, hardens SSH
      (key-only, no root password login). Tagged `app:tech-feed-reader,env:prod`.
- [x] **`firewall.tf`** — DO cloud firewall. Inbound: 22 from your
      `allowed_ssh_cidrs` only, 80 + 443 + ICMP from anywhere.
- [x] **`spaces.tf`** — DO Space `tech-feed-reader-backups` (private)
      with lifecycle rules (14d daily, 60d weekly, 400d monthly).
- [x] **`dns.tf`** — DigitalOcean DNS. References the zone via
      `data "digitalocean_domain"` (read-only) and creates ONE
      `digitalocean_record` A record at `${app_subdomain}.${domain}`
      → Droplet IP. The apex / other subdomains stay untouched so
      the user can park additional apps on the same zone.
- [x] **`outputs.tf`** — droplet IPv4 + ID, backups bucket name +
      endpoint, public URL, ready-to-paste SSH command.
- [x] **`terraform/README.md`** — bootstrap instructions.
- [x] **`terraform/.gitignore`** — keeps `terraform.tfvars`, `.terraform/`,
      state files out of git.

State storage: starts with local state in `terraform/terraform.tfstate`
(gitignored). If we want remote state later, DO Spaces with S3 backend
is one config-block away.

**Total provisioned monthly cost: ~$12 Droplet + ~$5 Spaces = ~$17/mo.**

## Phase 3 — Deploy + cutover (TOGETHER)

- [ ] **`terraform apply`** — provisions Droplet, firewall, Space,
      DNS records. Outputs the IP.
- [ ] **SSH into Droplet**, populate `/opt/app/.env` with production
      values (the secrets from Phase 0). Don't commit; this file lives
      only on the host.
- [ ] **`docker compose up -d`** — pulls images, starts the stack.
      Caddy auto-mints the Let's Encrypt cert.
- [ ] **Initialize schema** — `docker compose exec app rake db:migrate`
      (or the equivalent invocation of `Database.migrate!`).
- [ ] **Smoke test** — sign up a fresh user, add a feed, refresh it,
      read an article, mark feedback, run /triage, view /admin/dev-stats.
- [ ] **HSTS** — Caddyfile already sets `Strict-Transport-Security:
      max-age=21600` (6h) while we verify TLS works end-to-end.
      Bump to `max-age=31536000` (1y) in Caddyfile after a week of
      stability + redeploy.

## Phase 4 — Operations (CLAUDE)

- [ ] **Backup cron** on the Droplet: nightly `sqlite3 .backup` of
      `/var/lib/docker/volumes/app_data/_data/app.db` (use the SQLite
      online backup API so a writer doesn't get blocked), then `s3cmd
      put` to the DO Space. Daily into `daily/`, weekly tag into
      `weekly/`, monthly tag into `monthly/`. Retention is enforced by
      the bucket's lifecycle rules (see `terraform/spaces.tf`).
- [ ] **Restore-test script.** Pulls the latest dump into a sandbox
      container, runs `Database.migrate!` (idempotent), checks
      `SELECT COUNT(*) FROM articles`. Run quarterly.
- [ ] **Uptime monitor.** UptimeRobot (free) pointed at `/health`.
      Alert via email.
- [ ] **Caddy access logs** rotated daily, kept 14 days.
- [ ] **Runbook in `docs/runbook.md`** — common ops: deploy a new
      version, rotate a secret, restore from backup, restart a
      misbehaving service, SSH access, log inspection.

## Phase 5 — PostgreSQL migration (CLAUDE)

**Status: `next`** — decided 2026-05-17. The "Deferred to v1.1" note in Phase 1 above is now obsolete: rather than build nightly SQLite backup tooling that becomes throwaway when PG lands, ship PG and let DO managed PG handle backups (free 7-day point-in-time recovery on the $15 tier). Data-loss window between v1.0 and Phase 5 cutover is accepted; only ~1 day of usage at decision time and the user picked "migrate the data" so we'll preserve what's there.

5 PRs + 1 manual cutover step. Each PR is independently green; the cutover happens after all five land.

### D-PG-1 — `pg` gem + Database adapter abstraction (PR)

Goal: app supports both SQLite and Postgres at the connection layer. SQLite stays the default for `make run` / `make test`; PG is opt-in via `DATABASE_URL`.

- `Gemfile`: add `pg`
- [`app/database.rb`](app/database.rb): detect `DATABASE_URL` → return a wrapper around `PG::Connection`; else SQLite as today
- Thin **adapter** wraps the dialect differences the stores rely on:
  - `.execute(sql, args)` — args interpolated as `?` (SQLite) or `$1, $2…` (PG)
  - `.transaction { ... }` — same in both
  - `.last_insert_row_id` → in PG this consults `RETURNING id` from the last `execute`
  - `.changes` → `cmd_tuples` on the last PG result
- Spec suite stays green in SQLite mode; nothing observable yet to the user.

### D-PG-2 — Postgres migrations + CI matrix (PR)

Goal: `make migrate` produces an identical schema in both modes.

- New `db/migrations-postgres/` directory with PG-dialect versions of every migration (001–023+).
- Big piece: **FTS5 → `tsvector` + GIN index** on `articles`. The `articles_fts` virtual table goes away in PG mode; a generated `tsvector` column (`title || ' ' || coalesce(content_text, '')`) + a `GIN` index on it replaces it. Search queries route through the dialect-aware path landing in D-PG-3.
- `Database.migrate!` reads from `db/migrations/` (SQLite) or `db/migrations-postgres/` based on detected dialect.
- CI matrix: existing SQLite job + new Postgres job using `postgres:16-alpine` GitHub Actions service container, `DATABASE_URL` set, full RSpec.

### D-PG-3 — SQL audit + dialect-aware stores (PR)

Goal: hand-rolled SQL in stores works against both backends. Specs pass in CI matrix on both.

Hot spots, by store:
- `ArticlesStore` — `INSERT OR IGNORE` (import), `INSERT OR REPLACE` (categories backfill), `articles_fts MATCH` (search, for_topic), `datetime('now')` (a few places), `last_insert_row_id`.
- `FeedsStore` — `INSERT OR IGNORE` (catalog), `last_insert_row_id` (add_to_catalog).
- `ReadStateStore` — `INSERT ... ON CONFLICT(user_id, article_id) DO UPDATE ...` (SQLite supports this; PG too). Verify.
- `Recommendation` + `TopicClusters` — search hot path via FTS5; switch to `tsvector @@ plainto_tsquery` in PG mode.
- `Database.adapter` accessor lets each store branch when needed; goal is to push branching into the adapter where possible, not into the store.

### D-PG-4 — Provision PG cluster in Terraform (PR)

Goal: `terraform plan` cleanly proposes a PG cluster + firewall update. **No `apply` yet** — that happens in D-PG-5.

- New `terraform/database.tf`: `digitalocean_database_cluster` (engine `pg`, version `16`, smallest tier `db-s-1vcpu-1gb` = $15/mo, NYC3, 1 node).
- `terraform/firewall.tf`: tighten — only the Droplet's reserved IP can reach the cluster's 25060 port (DO managed PG runs on its own private network anyway, but defense in depth).
- New output: `db_connection_string` (sensitive). Includes `?sslmode=require` since DO managed PG requires TLS.
- No new variables; cluster name derived from `var.app_subdomain` + `-pg`.

### D-PG-4.5 — Data-migration script (PR)

Goal: `scripts/dump_sqlite_to_postgres.rb` reads the live Droplet SQLite into a freshly-migrated PG database, preserving IDs.

- One-shot script; reads `data/app.db`, writes via `pg` gem against `$DATABASE_URL`.
- Tables in FK-safe order: `users` → `feeds` → `articles` → `user_feed_subscriptions` → `read_state` → `feed_feedback` → `mute_rules` → `tags` → `article_tags` → `summaries` → `digests` → `triages` → all sports tables → `webauthn_credentials` → `recovery_codes` → `background_pool`.
- After insert, bump every PG sequence to `MAX(id) + 1` so the next AUTOINCREMENT doesn't collide.
- Spec: round-trip a tiny SQLite fixture into a Postgres fixture and `diff` row counts per table.

### D-PG-5 — Cutover (manual operations, no PR)

- Bring up the cluster: `terraform apply` in `terraform/` (creates the DB, ~5–10 min).
- `terraform output -raw db_connection_string` → drop into the Droplet's `/opt/app/.env` as `DATABASE_URL=...`.
- SSH to Droplet, **pull the latest image with PG support**: `cd /opt/app && git pull && docker compose build app sidekiq && docker compose up -d` (which auto-runs migrations against PG via `Database.migrate!` on boot).
- Verify PG has the empty schema: `docker compose exec app ruby -e "require_relative 'app/database'; p Database.connection.execute('SELECT COUNT(*) FROM users')"`
- Stop the app (`docker compose stop app sidekiq`), run the migration: `docker compose run --rm app ruby scripts/dump_sqlite_to_postgres.rb`
- Start back up: `docker compose up -d`
- Smoke test sign-in (passkey still works because RP_ID didn't change), verify feeds and read-state survived, verify search returns results, verify a /chat round-trip.
- Update DEPLOYMENT.md to mark Phase 5 complete; note the SQLite volume is now unused (can `docker volume rm app_app_data` after a few days of stability).

## Out of scope for v1 deploy (revisit later)

- Multi-region / failover (you have one Droplet, one region)
- Blue/green deploy (just `docker compose pull && up -d` for now)
- Remote terraform state (local state fine for solo dev)
- Per-user object storage (no user uploads exist)
- CI/CD auto-deploy on push to main (manual `git pull && docker
  compose up -d` is fine until traffic justifies the automation)
