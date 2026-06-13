# Agent Instructions — Tech Feed Reader

Operational reference for agents (and humans) working in this repo. The user-facing brief lives in [SPEC.md](SPEC.md); this file focuses on architecture, gotchas, and conventions that aren't obvious from a quick code read. Update it as code lands so it stays a current-state reference, not a planning document.

## Working with the user

**Pause for explicit user go-ahead before any of these — every time, no exceptions:**

- `git commit`
- `git push`
- `gh pr create`
- `gh pr merge`
- `git pull` after a merge to re-sync local

If the user grants batch authority for a specific run ("commit, push, merge when CI is green"), honour exactly that scope — but do **not** extrapolate to the next feature. The next round needs its own approval. A previous "yes" is not a standing yes. (See also [CONTRIBUTING.md → Memory-backed workflow rules](CONTRIBUTING.md#memory-backed-workflow-rules) — this file restates the rule because it's load-bearing and easy to miss.)

**Standard flow** (per [CONTRIBUTING.md](CONTRIBUTING.md)):

1. Branch off main into `outten/feature-description-NN` (e.g. `outten/stock-sparklines-87`). The older `outten/TODO-NNN` form also works. Don't push to `main` directly.
2. Implement + write tests + update docs in the same change.
3. `make test` locally → must be 0 failures.
4. **Pause — user approval required before committing.** Show the diff / commit message and wait for explicit go-ahead. For UI changes, the user must also manually verify the page in the browser before approving.
5. Commit, push the branch, open the PR (`gh pr create`). **Opening a PR also requires explicit user approval** — do not auto-open after every task. Ask first; bundle related items into one PR. **Exception: doc-only changes** (STUFF.md, README.md, AGENTS.md, about.erb, etc. — no code, no tests) may be committed on a branch and merged directly to main without a PR.
6. **Wait for CI green** on the PR before claiming "shipped" — CI is at [.github/workflows/ci.yml](.github/workflows/ci.yml) and runs RSpec + script syntax check on every push to `main` and every PR.
7. **Only the user merges PRs.** Never call `gh pr merge` unless the user explicitly instructs it for this specific PR. A previous merge approval does not carry over to the next PR.
8. **Production deploy** — the user says "deploy" or "go" and the agent runs `make deploy-patch` (or minor/major). This bumps VERSION, commits, tags, pushes, and the GitHub Actions deploy workflow handles the build + SSH. The agent may execute this step on explicit instruction; it may not decide to deploy on its own. Never run `make deploy-*` speculatively. After a deploy, sync local: `git checkout main && git pull --ff-only origin main && git remote prune origin`.

**Summary of the four gates — each requires its own explicit user instruction:**

| Gate | Action blocked until approved |
|---|---|
| Code review | `git commit` (+ browser verify for UI changes) |
| PR creation | `gh pr create` |
| PR merge | Only the user merges on GitHub |
| Production deploy | User says "deploy" → agent runs `make deploy-patch` → GH Actions builds + ships |

**UI approval gate** — for any change that affects what a human sees in a browser (views/, public/*.js, public/*.css, anything click-driven), the "pause before staging" in step 4 means: **green specs are not enough**. The user must manually verify in the browser and explicitly approve before `git commit`. Specs caught the data-layer plumbing on STUFF #23 but missed two JS/CSS bugs (a `hidden` attribute overridden by a `display: inline-flex` rule; a `button.disabled = true` inside the submit handler that cancelled the form submission) — both only visible by clicking the actual button. Backend-only changes (stores, migrations, scripts) don't trigger the gate.

**Documentation rule** — every PR that changes behaviour updates the touched docs in the same PR. The bar is "no doc reads as untrue after this PR." Concretely, when shipping a new page or module, update:
- [README.md](README.md) page table + status line
- AGENTS.md (this file) — if there's a new module / store / external integration / convention worth documenting
- [CONTRIBUTING.md](CONTRIBUTING.md) — only if the process itself changed
- **[TODO.md](TODO.md) and [STUFF.md](STUFF.md)** — these are the live backlog. Every PR that ships work captured in either file must flip the relevant item's checkbox + status (e.g. `**Status: tests** → **Status: merged** — commit \`abc1234\``) in the same change. Items intentionally not implemented get an explicit "declined" or "deferred" annotation with a one-line reason — never leave a stale `[ ]` for work we've decided not to do. New asks added to STUFF.md by the user during a session should land in their PR with status `not implemented`; the next PR that addresses them flips the status.

Don't leave docs to be reconciled later. The "rewrite the file" sweep we did in `outten/TODO-049` is what NOT to repeat — every PR should keep these files honest as it lands.

**Catch-up skill** — if drift does happen (e.g. someone merged in another session without touching docs), invoke `/update-docs` (the skill at [.claude/skills/update-docs/SKILL.md](.claude/skills/update-docs/SKILL.md)). It scans recent merges and proposes precise edits to README / AGENTS / TODO / STUFF. Read-only on code; edits docs only.

## Shell commands

Prepend shell commands with `snip` to compress verbose output and cut token usage — e.g. `snip git log -10`, `snip ls -la`, `snip grep -r foo`. The wrapper is pass-through for short output and summarises long output, so wrapping is safe by default. Skip it only when exact stdout matters (test-runner output you'll parse, command output piped into another tool, or anywhere you've been asked for the raw bytes).

## Setup & credentials

Credentials live in `.credentials` (NOT `.env`). Both files are auto-loaded by [`app/credentials.rb`](app/credentials.rb), which is required at the top of `app/main.rb` and `app/sidekiq_boot.rb` so both processes get the same env. `.credentials` wins — `.env` is honoured but secondary.

**Key aliasing**: `app/credentials.rb` aliases `CLAUDE_API_KEY → ANTHROPIC_API_KEY` at load time, since the Anthropic SDK reads `ANTHROPIC_API_KEY` from env but the friendlier name is what users put in `.credentials`. Set either; the app uses whichever is present.

**Wired keys**:

| Key | Purpose |
|---|---|
| `CLAUDE_API_KEY` (or `ANTHROPIC_API_KEY`) | Claude API for LLM summarization, the `/chat` widget, and digest summaries. Optional at startup — the app degrades gracefully (extractive summarizer; chat widget hides itself; digests fall back to extractive / excerpt). |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | When set, the OpenTelemetry SDK installs the OTLP exporter alongside the in-memory recorder; spans flow to your collector (Jaeger / Tempo / Honeycomb / …). Unset → recorder-only, browse at `/admin/traces`. |
| `OTEL_SERVICE_NAME` | Resource attribute attached to every span. Defaults to `tech-feed-reader`. |
| `TRACING_RECORDER_CAPACITY` | Ring-buffer size for `Tracing::Recorder` (default `200`). |
| `REDIS_URL` | Sidekiq broker. Defaults to `redis://localhost:6379/0`. |
| `RETENTION_DAYS` | Article retention window for [`Pruner`](app/pruner.rb). Default `7`. Sweep runs at the end of `make refresh-feeds` and standalone via `make prune`. |
| `PRUNE_KEEP_UNREAD` | Set to `1` to preserve unread articles past the retention window (default sweeps unread + read). Bookmarked articles are always kept. |
| `PRUNE_ON_REFRESH` | Set to `0` to skip the post-refresh sweep on a given `make refresh-feeds` run. |
| `FINNHUB_API_KEY` | Finnhub stock API (free tier, 60 req/min). Powers `/stocks` search, detail, the global ticker (every signed-in page, via the `ticker_quotes` helper), and the hourly `IndexSyncWorker`. Optional — stock quote features hide when unset (per-symbol news via Yahoo RSS needs no key). **Production**: must be in both `.env` and `docker-compose.yml` environment blocks (app + sidekiq). |

**Logging**: every HTTP request, feed fetch, refresh, Claude call, chat turn, digest run, and Sidekiq job emits a single-line JSON event to STDOUT via [`app/logger.rb`](app/logger.rb). Per-request lines come from [`app/request_log_middleware.rb`](app/request_log_middleware.rb), which sits at the Rack layer so it sees static assets too (Sinatra `after` filters skip them). Defaults: `debug` in dev, `info` in `RACK_ENV=staging` / `production`, `fatal` in `test`. `LOG_LEVEL=debug|info|warn|error|fatal` overrides. Pipe through `jq` for pretty-printing: `make run | jq -c`.

No other API keys required — RSS / Atom feeds are public and unauthenticated. **Never commit `.credentials` or `.env`** — both are git-ignored.

## Development commands

```bash
make install                 # bundle install
make migrate                 # apply any pending db/migrations/*.sql (idempotent)
make seed-feeds              # insert FeedCatalog::seed_defaults (5 starters; 108-entry catalog browsable on /feeds)
make run                     # auto-reload via rerun → http://localhost:4567 (alias: make dev)
make serve                   # one-shot run, no auto-reload
make test                    # RSpec
make refresh-feeds           # poll every feed in FeedsStore once
make refresh-feed FEED=...   # poll one feed by URL or id
make scheduler               # long-running poller honouring per-feed intervals
make sidekiq                 # background-job worker (needs Redis up)
make redis                   # foreground Redis (alternative to brew services)
make digest                  # generate + persist a digest snapshot (read at /digests; cron-friendly)
make prune                   # delete articles older than RETENTION_DAYS (default 7); bookmarks always kept
make backfill-podcast-images # fill feeds.image_url via iTunes Search for podcasts missing <itunes:image>
make seed-sports-data        # seed sports_leagues + sports_teams + sports_follows for user-followed teams (idempotent)
make sync-sports             # daily ESPN sync — pulls match schedules + scores for every followed team into sports_matches
```

**One-shot dev session orchestration** — pre-canned for tracing-enabled local runs:
```bash
make run-all                 # Jaeger + Redis (if needed) + web + sidekiq, all backgrounded; opens browser tabs
make stop-all                # symmetric teardown (only stops the Redis it started itself)
make jaeger / jaeger-stop    # just the Jaeger container
make serve-otel              # `make serve` with OTEL_EXPORTER_OTLP_ENDPOINT pointed at local Jaeger
make sidekiq-otel            # same wiring for the Sidekiq worker
```

`make run` auto-migrates on boot, so `make migrate` is mainly for CI / scripts that need the DB up before the web process starts.

`make run` reads [.rerun](.rerun) for watch dirs and ignore globs. **`.rerun` does NOT support `#` comments** — its contents are shell-split verbatim. Keep it option-only.

## Storage architecture

**PostgreSQL** is the source of truth for feeds, articles, read state, tags, summaries, sports data, and pageviews. Production runs against a DigitalOcean Managed PG cluster; dev points at a local Postgres via `DATABASE_URL`. Foreign keys cascade on delete (drop a feed → its articles + their read_state + summaries + article_tags rows go too); the `articles` table carries a generated `tsv` tsvector column for `ts_rank` / `ts_headline`-based search.

This replaces `t-money-terminal`'s file-per-store + mutex + atomic-rename pattern. PG transactions handle atomicity; we don't need to roll our own.

**Schema lives in [db/migrations-postgres/](db/migrations-postgres/).** The runner is [app/database.rb](app/database.rb) — `Database.migrate!` is idempotent, applies any pending migration files in filename order, and is called automatically on web-app boot (skipped under `RACK_ENV=test`). `make migrate` is the explicit one-shot entry point.

Article bodies, extracted content, and summaries all live in PG.

**Retention policy** — articles older than `RETENTION_DAYS` (default 7) get swept by [`Pruner`](app/pruner.rb). Bookmarked articles are always preserved regardless of age; set `PRUNE_KEEP_UNREAD=1` to also preserve unread items past the window. Cascades take care of `read_state`, `summaries`, and `article_tags`; the `tsv` column lives on `articles` itself so deletes need no separate index sweep. Wired in two places:

- `scripts/refresh_feeds.rb` runs `Pruner.prune_old` at the end of every refresh-all cycle. Override with `PRUNE_ON_REFRESH=0` to skip the sweep on a given run.
- `make prune` (= `scripts/prune_articles.rb`) runs the same sweep standalone — useful in cron / launchd if you want a separate retention cadence from the refresh cadence.

The cutoff is `COALESCE(published_at, fetched_at) < now - retention_days`, so feeds that don't ship a publish date still get swept based on when we first saw them.

**Per-feed TTL** (analogous to `t-money`'s market-aware TTL) — the `feeds.fetch_interval_seconds` column is the source of truth; the table below is just the suggested default at add-time:

| Feed cadence | Default poll interval |
|---|---|
| High-frequency (HN, Lobsters, /r/programming) | 15 min |
| Major publishers (Ars, Verge, NYT-tech, …) | 1 h |
| Personal blogs / low-volume | 4–6 h |

**Rendering contract** (load-bearing — break it and pages get slow):

```
Page renders MUST be cache-only.
  /dashboard, /articles, /article/:id → PG reads only

Network events ONLY happen via:
  - Scheduled poll (make scheduler)
  - Manual refresh (POST /refresh/{feed,all})
  - Adding a new feed (POST /feeds)
  - User-initiated summarize on /article/:id (Claude API call)
```

Hard test will live in `spec/articles_perf_spec.rb` (mirrors `t-money`'s `portfolio_perf_spec.rb`) asserting `not_to receive(:fetch_feed)` on `/articles` and `/dashboard` render.

## Tables

| Table | Purpose |
|---|---|
| `users` | Phase A1: id, username (lowercase, unique), display_name, created_at, last_seen_at. Identity is username-only — no email, no phone. |
| `webauthn_credentials` | Phase A1: per-user passkey records. credential_id (unique), public_key (BLOB), sign_count, transports, label, last_used_at. Multiple per user supported (phone + laptop). FK CASCADE on users. |
| `recovery_codes` | Phase A1: 10 single-use codes per user, hashed with HMAC-SHA256 keyed by `SESSION_SECRET`. consumed_at set on use. FK CASCADE on users. |
| `feeds` | Subscribed feeds: url, title, fetch_interval_seconds, last_fetched_at, last_etag, last_modified, last_status, topic, image_url. **Shared catalog** — one row per URL across all users; subscriptions live in `user_feed_subscriptions`. |
| `user_feed_subscriptions` | Phase A2: bridge (user_id, feed_id) unique. One fetch keeps every subscriber up to date. |
| `articles` | Article history: id (BIGSERIAL), uid (SHA1 slug), feed_id, title, url, author, published_at, content_html, content_text, audio_url, audio_mime_type, audio_duration_seconds, image_url, `categories` (JSON-encoded publisher tags, STUFF #28.2), generated `tsv tsvector` column for full-text search |
| `read_state` | Per-article state: read, bookmarked, archived, opened_at, feedback (explicit ±1, Phase 3), passive_feedback (derived from listened-%, Phase 4). Phase A2: composite PK `(user_id, article_id)`. |
| `feed_feedback` | Per-feed weight (Phase 3): weight REAL DEFAULT 1.0, clamped to [0.25, 3.0] by `FeedFeedbackStore`. Phase A2: composite PK `(user_id, feed_id)`. |
| `mute_rules` | Hard-hide rules (Phase 5): kind ∈ `{keyword, author, feed}`. Phase A2: composite PK `(user_id, kind, value)`. Applied as a NOT EXISTS sub-query in `ArticlesStore.state_query` |
| `tags` / `article_tags` | User tag rules + article-tag bridge. Phase A2: `tags` carry `user_id` with UNIQUE `(user_id, name)`; matcher runs every user's rules at import time and writes one `article_tags` row per match. |
| `triages` | Phase 8 + STUFF #8: AI-classified unread snapshots. Phase A2: scoped by `user_id`. Stores `must_read` / `optional` / `skip` as JSON arrays of article uids + per-row `topic` + `raw` LLM payload. |
| `digests` | Phase 6 / STUFF #5: stored daily-digest snapshots; subject + text_body + html_body + LLM-summary cache (`llm_summary`, `llm_model`, `llm_generated_at`). Phase A2: `user_id`. |
| `sports_leagues` | Sports Phase S3: NFL / NBA / MLS / intl rugby etc., one row per league synced from a provider |
| `sports_teams` | Sports Phase S3: teams across all leagues, FK to `sports_leagues`. Idempotent upsert by `(source_provider, league_id, external_id)` |
| `sports_matches` | Sports Phase S3: scheduled / live / final games. FK to `sports_teams` (home + away). Status ∈ `{scheduled, live, final, postponed, cancelled}` |
| `sports_players` | Sports Phase S7: tennis players + per-player follows. ATP/WTA rankings cached in a separate sports_standings rollup. |
| `sports_follows` | Sports Phase S3: user's "I follow these" list. kind ∈ `{team, player, league}`. Phase A2: UNIQUE `(user_id, kind, value)`. |
| `sports_standings` | Sports Phase S8: per-league standings rollup (W / L / D / GF / GA / pts), refreshed via `make sync-sports`. |
| `sports_entity_articles` | Sports Phase S7 follow-up: bridge for "articles mentioning Sinner / Eagles" on per-entity pages. |
| `background_pool` | Pool of Picsum image IDs powering the per-page background. STUFF #21 doubled the pool to 100. |
| `stock_follows` | STUFF #85: per-user stock symbol follows. Mirrors sports_follows pattern. (user_id, symbol, name). |
| `stock_quotes` | STUFF #85: cached quote snapshots. One row per symbol, refreshed every 15 min by StockSyncWorker (followed symbols) and hourly by IndexSyncWorker (10 major indices via ETF proxies: SPY, DIA, QQQ, IWM, EWU, EWG, EWJ, EWH, EWQ, FEZ). Primary key is `symbol` (no id column). |
| *(stock news)* | Per-symbol news has **no new table** — `StockNewsFeed` (app/stock_news_feed.rb) maps a symbol to its Yahoo Finance per-symbol RSS feed (topic `finance`) in the existing `feeds` catalog, so its headlines flow through the ordinary feed→article pipeline. Following a symbol subscribes the user to that feed (surfacing its news in `/articles` + home); `GET /stocks/:symbol/news` re-renders just the section for the `stock-news.js` cold-start poller. |

**Recommendation modules** (Phase 6): `Recommendation` is the per-article "Articles like this" surfaced on `/article/:uid` (PG `ts_rank` over websearch_to_tsquery, no personalization). `Recommendation::ForYou` ([app/recommendation/for_you.rb](app/recommendation/for_you.rb)) is the personalised relevance ranker on `/articles?sort=relevance` — blends recency × per-feed weight × ±corpus overlap. Pure compute; no background job. Empty corpus collapses to chronological so a brand-new install is unaffected. `next_after(article)` (Phase 7) returns one suggestion for the Read-next card on `/article/:uid`, falling back to the full-text path when the corpus is cold.

**Triage::Claude** ([app/triage/claude.rb](app/triage/claude.rb), Phase 8) — AI-assisted unread classification. Pulls up to 30 unread + 20 corpus exemplars per side, prompts Claude (Sonnet 4.6, not Opus — cost guard) for structured JSON, parses defensively (strips markdown fences, salvages JSON from prose, falls back to "skip all" on parse failure rather than 500ing). Surfaces at `/triage`; manual POST trigger only — no DB persistence v1.
| `tags` | User tag rules: name, match_kind (regex/keyword/feed_id), match_value |
| `article_tags` | Many-to-many join between articles and tags |
| `summaries` | Cached summaries: extractive (always) + llm (on demand) |
| `digests` | Stored digest snapshots produced by `make digest`: subject, text_body, html_body, generated_at, window_hours, article_count |
| `schema_migrations` | Migration runner state |

`HealthRegistry` is in-memory only (bounded ring buffer of feed-fetch observations); surfaces at `/admin/health`, clears on process restart.

Per-store wrapper classes (`FeedsStore`, `ArticlesStore`, etc.) sit on top of the DB and present a higher-level API to the app — but the data lives in PG, not in JSON files.

## Authentication + multi-user (Phases A1 + A2)

[app/auth.rb](app/auth.rb) — passkey-only auth (WebAuthn) with one-time recovery codes as the lost-device fallback. No email, no SMS, no password. Username is the only identity field. Implementation uses the [`webauthn`](https://github.com/cedarcode/webauthn-ruby) gem (same library as Mastodon + GitLab); browser side is native `navigator.credentials.create()` / `.get()` with no library — see [public/auth.js](public/auth.js) for the ~240-LoC ceremony driver.

**Auth wall** — a Sinatra `before` filter on every request enforces sign-in unless the path is in the public allowlist (`/`, `/about`, `/health`, `/metrics`, `/sign-up`, `/sign-in`, `/sign-out`, `/api/auth/*`, plus static assets). The wall is OFF in `RACK_ENV=test` by default so existing specs don't need a sign-in dance; specs that explicitly want to exercise the wall flip `TechFeedReader.enforce_auth_wall = true` in a before/after pair (see [spec/auth_spec.rb](spec/auth_spec.rb)).

**Per-user data split (A2)** — every table that holds user-state carries a `user_id` FK with `ON DELETE CASCADE`, established in the consolidated PG baseline [db/migrations-postgres/001_init.sql](db/migrations-postgres/001_init.sql). Composite PKs / unique constraints widened to include `user_id`: `read_state(user_id, article_id)`, `feed_feedback(user_id, feed_id)`, `mute_rules(user_id, kind, value)`, `tags UNIQUE(user_id, name)`, `sports_follows UNIQUE(user_id, kind, value)`. `feeds` itself stays a shared catalog so one fetch keeps every subscriber up to date; per-user subscriptions live in `user_feed_subscriptions`. Every store method that touches user-state takes `user_id` explicitly — routes call `current_user_id`, defined in [app/auth.rb](app/auth.rb) as a Sinatra helper. Cross-user isolation is locked by [spec/cross_user_isolation_spec.rb](spec/cross_user_isolation_spec.rb).

**`/account` page** — manages display name, registered passkeys (list / + Add this device / Revoke per row), recovery-code regeneration (one-shot reveal), and account deletion (typed-username confirmation gate; cascade deletes via the per-user-FK chain wipe every per-user row). Lockout protection: refuses to revoke the user's last passkey when zero unused recovery codes remain.

**`/welcome` first-time onboarding** — `GET /` redirects signed-in users with zero feed subscriptions to `/welcome`. The page shows four topic chips (Technology / Sports / Nature / Podcasts); each selection seeds 4-6 curated starter feeds from `FeedCatalog::ONBOARDING_STARTERS` via the existing `FeedsStore.add_for_user` path, then `POST /welcome/subscribe` redirects to `/articles?notice=onboarded`. Brand-new feeds (no prior subscriber → `last_fetched_at` is nil) get a `FeedRefreshWorker` enqueued so content shows up within ~30s. Existing feeds (another user is already subscribed) skip the fetch — content is already imported.

## Article id

Each article has both a numeric primary key (`articles.id`, used internally for joins) and a stable `uid` = `SHA1(feed_url + article_url)[0,12]` used in URLs (`/article/abc123def456`). The uid is stable across re-fetches; the id is internal.

## Feed-fetch flow

```
1. SELECT row from feeds WHERE id = ?
2. GET feed_url with If-Modified-Since: feed.last_modified and If-None-Match: feed.last_etag
3. if 304 → record health observation, UPDATE feeds.last_fetched_at, return
4. if 200 → parse with feedjira (or rss stdlib), extract entries
5. for each entry whose uid is not already in articles:
     - run readability extraction on entry[:content] (single shared extractor)
     - INSERT into articles (the generated `tsv` column keeps full-text search in sync)
     - assign tags via tags-rule matcher → INSERT into article_tags
6. UPDATE feeds SET last_etag, last_modified, last_fetched_at, last_status WHERE id = ?
7. record HealthRegistry observation
```

## Provider waterfall (content extraction)

For articles where the feed body is a snippet, not full content, fall through providers in order — first non-empty wins:

| Source | Order | Module |
|---|---|---|
| Feed entry body | 1 | `FeedFetcher` (default) |
| Readability extraction of original page | 2 | `Providers::Readability` (single shared HTTP client + retry) |
| Archive.org / Wayback most-recent capture | 3 | `Providers::Archive` (last-resort, when origin returns 4xx/5xx) |

**Other providers**: [`Providers::ITunesLookup`](app/providers/itunes_lookup.rb) — fall-back podcast cover-art lookup against the iTunes Search API (no auth, ~20 req/min). Used by `make backfill-podcast-images` (`scripts/backfill_podcast_images.rb`) to fill `feeds.image_url` for podcast feeds whose RSS doesn't expose `<itunes:image>` or `<image><url>` (Vox-published Ezra Klein, etc).

**Sports data providers** (Phase S4): [`Providers::ESPN`](app/providers/espn.rb) wraps ESPN's reverse-engineered public endpoints (no auth) for structured match data. Two entry points: `team_schedule(sport_path:, team_external_id:)` (NFL / NBA / MLS — per-team season schedule in one call) and `league_scoreboard(sport_path:, dates:)` (rugby — the team_schedule endpoint 500s there). Defensive normalization with per-event rescue so one bad row doesn't poison a batch. Wired by `make sync-sports` (`scripts/sync_sports.rb`) which walks `sports_follows` and upserts into `sports_matches`. Seed via `make seed-sports-data`. **TheSportsDB integration deferred** — the free tier key '3' is poisoned at source (every search returns Arsenal); revisit when a working free provider surfaces or the user opts into TheSportsDB Patreon ($9/mo).

Mirror `t-money`'s `try_providers` pattern: log to `HealthRegistry.measure`, return first non-empty.

## HealthRegistry

[app/health_registry.rb](app/health_registry.rb) — bounded ring buffer of feed-fetch / extractor / summarizer observations. Surfaces at `/admin/health`. `HealthRegistry.degraded` powers the dashboard banner when feeds are systematically failing (e.g. user lost network connectivity, or a publisher killed an old RSS endpoint).

In-memory only; clears on process restart. Tests opt in via `ENV['HEALTH_REGISTRY']=1`.

## Claude integration

Two consumer modules sit on top of the `anthropic` SDK; both gracefully degrade when no key is set.

- **[`Summarizer::Claude`](app/summarizer/claude.rb)** — two flavours, both `claude-opus-4-7`, both cached so re-visits never re-spend tokens. `.summarize` is the one-shot LLM summary on `/article/:uid` ("Summarize with Claude" button), cached in the `summaries` table (column `llm`). `.summarize_digest` is the digest-level executive summary on `/digests/:id`, cached on the `digests` row (`llm_summary` / `llm_model` / `llm_generated_at`); the button only renders when no cache exists, and the route hard-skips the API call when one does. Neither is invalidated on feed re-fetch — LLM calls are expensive (see gotcha #7 below).
- **[`Chat::Claude`](app/chat.rb)** — conversational backend for the floating chat widget. Stateless on the server: each turn ships `{message, history, context: {url, title, excerpt}}`; the widget keeps history in `localStorage` keyed by `tfr.chat.<pathname>`. Uses `claude-sonnet-4-6` (chat trades depth for latency vs. the Opus summarizer). History capped to `MAX_HISTORY_TURNS` pairs; excerpt capped to `MAX_CONTEXT_CHARS`.

Both are wrapped in OTel `llm.summarize` / `llm.chat` spans with token-count attributes (see Tracing below).

The chat widget UI lives in [`public/chat-widget.js`](public/chat-widget.js) + the `<div id="chat-widget" data-turbo-permanent>` in [`views/layout.erb`](views/layout.erb). It hides itself entirely when `/chat/health` reports `available: false` (no API key). Per-page context flows via `window.PAGE_CONTEXT` set by an inline script in the layout — routes can populate `@chat_context = { title:, excerpt: }` to override the default (see [`/article/:uid`](app/main.rb) for an example that ships the article body).

## OpenTelemetry tracing

[`app/tracing.rb`](app/tracing.rb) boots the OTel SDK in non-test env. Auto-instrumentation via `opentelemetry-instrumentation-all` covers Sinatra, Rack, Net::HTTP, Sidekiq, and PG — every HTTP request, outbound fetch, job, and SQL query becomes a span automatically. Manual spans wrap `FeedFetcher#fetch_feed` (`feed.fetch`) and the two Claude paths (`llm.summarize`, `llm.chat`).

**Two span processors run side-by-side**:

- `RecorderProcessor` — process-local ring buffer (size `TRACING_RECORDER_CAPACITY`, default 200). Always on. Powers [`/admin/traces`](app/main.rb) so traces are useful out of the box without any external collector.
- `BatchSpanProcessor` + OTLP exporter — installed only when `OTEL_EXPORTER_OTLP_ENDPOINT` is set. Ships spans to your collector (Jaeger / Tempo / Honeycomb / …). The OTLP gem is lazy-loaded so dev runs without the env var pay zero protobuf init cost.

Web and worker each have their own recorder (process-local). Cross-process correlation requires the OTLP exporter — `make run-all` wires the local Jaeger automatically.

## Digests

[`Digests`](app/digests.rb) (note plural — avoids clashing with Ruby's stdlib `Digest`) composes a snapshot of unread articles in the last `DIGEST_WINDOW_HOURS` (default 24). Joins `articles ↔ feeds ↔ read_state ↔ summaries` in one query; summary precedence is **LLM → extractive → 240-char content excerpt**. Renders both a plain-text body and an HTML fragment that drops directly into `views/digest.erb`.

Persistence is in [`DigestStore`](app/digest_store.rb) → the `digests` table. The cron entry point is [`scripts/generate_digest.rb`](scripts/generate_digest.rb) (`make digest`); each run inserts a new row, so wiring it once a day yields one row per day. Browse at `/digests`; detail at `/digests/:id`.

No email — earlier iterations shipped via SMTP; the user's preference is to keep digests in-app. The composer's text body is kept around as a debugging aid and for any future re-export.

## Persistent mini-player (Hotwire Turbo)

The `<audio>` element + mini-player UI live in [`views/layout.erb`](views/layout.erb) under `<div id="global-player" data-turbo-permanent>`. Hotwire Turbo (loaded via CDN in `<head>`) intercepts link clicks + form submits and swaps `<body>` via XHR, but `data-turbo-permanent` elements survive untouched — so audio keeps playing across navigations. Same trick keeps the `#chat-widget` panel + open state across navs.

The singleton player API lives in [`public/global-player.js`](public/global-player.js) as `window.Player` (`load`, `pause`, `resume`, `toggle`, `close`, `state`, `isActive`, `isPlaying`). Article pages render a `<button class="play-episode" data-…>` that calls `Player.load(...)` instead of carrying their own `<audio>`.

**Two flavours of localStorage persistence**:

- `tfr.podcast.now_playing` — full snapshot (uid, url, mime, title, articleUrl, duration, currentTime, paused, rate). Restored on hard reload; resumes paused since browsers block autoplay on a fresh document.
- `tfr.podcast.position.<uid>` — per-episode resume position (existing convention). Cleared on `ended`.

**Turbo migration notes** — body-level `<script>` tags re-execute on every Turbo body swap. Scripts that should bind once need a guard (see `window.__playerInited` in `global-player.js` and the `dataset.inited` check in `chat-widget.js`). Scripts that should rebind every nav (e.g. the article-page hookup of the play-episode button) can run unconditionally.

**Nav-dropdown hover gap + click-to-toggle** — the Browse ▾ / AI ▾ / Manage ▾ dropdowns use CSS `:hover`/`:focus-within`. There is a 4 px gap between the trigger and the menu panel; without a bridge the hover state breaks when the cursor moves downward and the menu vanishes before the user reaches it. Fix is a `::before` pseudo-element on `.nav-dropdown` with `padding-top` matching the gap — invisible but keeps the hover active. A JS click-to-toggle (`.open` class) is also wired in [`public/nav-dropdown.js`](public/nav-dropdown.js): click pins the menu open; closes on outside click, Escape, or any menu-item selection. Don't remove the `::before` bridge or the `open` class without checking both paths.

**Turbo opt-out for heavy-JS pages** — for pages that initialize a complex JS component (Chart.js on `/admin/dashboard`, the YouTube IFrame API on `/article/:uid` for video articles) OR that submit a form to a long-running endpoint (the `/triage` Generate button calls Claude for ~30s), Turbo's silent background fetch is the wrong default. Either the click looks dead, the canvas is stuck stale, or the body-replace races the script's first run. Mark the *link* or *form* with `data-turbo="false"` for those targets. PR #62 / #65 / #69 cover the three real-world incidents that taught us this — when in doubt, opt out.

## Project structure

```
app/
  main.rb                          # Sinatra routes; auto-migrates on boot
  credentials.rb                   # loads .credentials/.env; aliases CLAUDE_API_KEY → ANTHROPIC_API_KEY
  database.rb                      # PG connection handle + migration runner
  logger.rb                        # JSON-line structured logger
  request_log_middleware.rb        # Rack middleware: per-HTTP-request JSON log line (sees static assets too)
  version.rb                       # AppVersion::GIT_SHA + STARTED_AT (used by /health, OTel resource)

  # Auth (Phase A1)
  auth.rb                          # WebAuthn config + current_user / require_signed_in! helpers + before-filter
  users_store.rb                   # users CRUD: create / find / update_display_name! / delete!
  webauthn_credentials_store.rb    # passkey records: register! / delete_for_user! / bump_sign_count!
  recovery_codes_store.rb          # mint_for! / consume! / regenerate_for! — HMAC-SHA256 codes
  stopwords.rb                     # STUFF #28.5: single home for STOPWORDS::GENERAL / PHRASE / CATEGORY

  # Feeds + articles core
  feed_fetcher.rb                  # conditional GET → parse → update FeedsStore (OTel feed.fetch span)
  feed_parser.rb                   # feedjira wrapper; normalises RSS 2.0 / RSS 1.0 / Atom; extracts entry.categories
  feed_catalog.rb                  # curated 227-entry catalog across 19 topics + seed_defaults + recommend_for personalisation
  feeds_store.rb                   # feeds + user_feed_subscriptions bridge; popular_by_type for #24 top charts
  articles_store.rb                # articles + tsvector search + audio + categories backfill; podcast_feeds + youtube_channels
  read_state_store.rb              # per-user-per-article read / bookmark / archive / feedback
  feed_feedback_store.rb           # per-user-per-feed weight (Phase 3)
  mute_rules_store.rb              # per-user keyword / author / feed hard-hide rules (Phase 5)
  tags_store.rb / tags_applier.rb  # per-user tag rules + cross-user tag-snapshot matcher at import time
  sanitizer.rb                     # loofah whitelist; sanitize_html + text_only

  # Providers (external HTTP)
  providers/
    http_client.rb                 # shared user-agent + retry/backoff + 301/302 redirect-following
    readability.rb                 # main-content extraction (teaser-feed fallback)
    itunes_lookup.rb               # podcast cover-art + Apple-Podcasts URL → RSS resolver
    espn.rb                        # NFL / NBA / MLS / rugby — reverse-engineered public endpoints
    youtube_channel_resolver.rb    # STUFF #30: @handle / /channel/UC… → canonical feed URL

  # Summaries + LLM
  summary_store.rb                 # extractive + LLM summaries cache
  summarizer/
    extractive.rb                  # frequency-based picker; references Stopwords::GENERAL
    claude.rb                      # Anthropic SDK wrapper for article + digest summaries (Opus 4.7)
  chat.rb                          # Chat::Claude — page-context chat backend (Sonnet 4.6)

  # AI feeds + triage
  feed_recommender/claude.rb       # STUFF #23: ✨ Ask AI for feed ideas on /feeds
  triage/claude.rb                 # Phase 8: /triage classifier (Sonnet 4.6)
  triage_store.rb                  # persisted triage runs per user per topic
  digests.rb / digest_store.rb     # daily-digest composer + persistence; LLM summary cached on the row
  recommendation.rb                # ts_rank-overlap "Related" panel + top_keywords + top_phrases (#28.4)
  recommendation/for_you.rb        # personalised ranker for /articles?sort=relevance
  topic_clusters.rb                # /topics weighted-scoring clustering (STUFF #28)

  # Radio (STUFF #81)
  radio_catalog.rb                 # 32 curated commercial-free stations in 5 groups (SomaFM, FIP/Radio France, Swiss Radio, Public Radio, Independent)
  radio_store.rb                   # radio_stations + radio_follows; seed_catalog!, follow!, unfollow!
  radio_recommender/claude.rb      # AI station recommendations from a free-text prompt

  # Sports
  sports_teams_store.rb / sports_leagues_store.rb / sports_matches_store.rb
  sports_players_store.rb / sports_follows_store.rb / sports_standings_store.rb
  sports_entity_articles_store.rb  # cross-store: articles mentioning a followed entity
  sports_teams.rb                  # sports team registry + slug helpers

  # Infra
  background_pool.rb               # Picsum image-id pool (100 images, refreshable from /admin/backgrounds)
  pruner.rb                        # retention sweep — delete articles older than RETENTION_DAYS
  health_registry.rb               # bounded ring buffer of feed-fetch observations
  metrics.rb / metrics_middleware.rb / sidekiq_metrics_middleware.rb  # Prometheus + Sidekiq
  tracing.rb                       # OpenTelemetry SDK boot + RecorderProcessor + optional OTLP exporter
  scheduler.rb                     # due-feed picker + refresh_one helper
  sidekiq_boot.rb / sidekiq_config.rb  # worker boot + middleware wiring
  workers/feed_refresh_worker.rb   # background job that refreshes a single feed
  workers/stock_sync_worker.rb     # every 15 min: refresh followed stock symbols via Finnhub
  workers/stock_quote_fetch_worker.rb  # eager single-symbol fetch on follow
  workers/index_sync_worker.rb     # hourly (:05): refresh 10 major world indices (ETF proxies)
  stock_news_feed.rb               # symbol → Yahoo per-symbol RSS feed; followed-symbol news rides the feed→article pipeline

db/
  migrations/                      # 23 migrations; runner in app/database.rb applies in filename order
    001_init.sql                   # initial schema (feeds, articles, articles_fts, read_state, tags, …)
    002_articles_audio.sql … 022_a2_per_user_data.sql + 023_articles_categories.sql

views/                             # ERB templates
public/
  style.css                        # all CSS lives here (light + dark) — ~4000 LoC
  global-player.js                 # singleton Player + mini-player UI bindings
  chat-widget.js                   # floating chat button + panel + /chat client
  header-refresh.js                # AJAX refresh-all button
  feeds.js / feeds-ai.js / feeds-filter.js  # /feeds: add feed / AI recommender / search+chip toolbar
  auth.js                          # WebAuthn ceremony driver (signup / signin / recovery / +add passkey)
  youtube-watch.js                 # YouTube IFrame API watch-progress tracking
  nav-dropdown.js                  # Browse/AI/Manage dropdown: hover bridge + click-to-toggle (.open class)
  stock-sparklines.js              # fetch /api/stocks/sparklines, draw canvas intraday charts on index cards
  stock-news.js                    # /stocks/:symbol cold-start poller — polls /stocks/:symbol/news, swaps the section in when the feed warms
  mutes-tags.js                    # AJAX add/delete for mute rules (/feeds) and tag rules (/tags); no scroll loss

scripts/
  migrate.rb / seed_feeds.rb / seed_user.rb / scheduler.rb
  refresh_feed.rb / refresh_feeds.rb / fix_article_links.rb
  generate_digest.rb / prune_articles.rb / generate_triage.rb
  seed_sports_data.rb / sync_sports.rb / backfill_podcast_images.rb / backfill_audio.rb
  dedup_sports_teams.rb / normalize_team_slugs_to_catalog.rb  # STUFF #68 + #69 one-shot data fixes
  backfill_stock_news_feeds.rb    # one-shot: subscribe pre-existing stock follows to their Yahoo news feed
  capture_home_screenshots.rb     # marketing screenshot capture (boots app on :4569 with auth bypassed)
  bump_version.rb                  # VERSION bump for release-{major,minor,patch}
  run_all.sh / stop_all.sh         # orchestrate Jaeger + Redis + web + sidekiq for one-command dev

spec/                              # RSpec (test env: PG via TEST_DATABASE_URL, no real HTTP, auth wall OFF by default)
.github/workflows/ci.yml           # RSpec + scripts syntax check on push to main + every PR
.github/workflows/deploy.yml       # tag-triggered (v*): test job → build linux/amd64 image → push to DOCR → SSH deploy
```

## Testing

```bash
make test                                  # full suite
bundle exec rspec spec/feed_fetcher_spec.rb
bundle exec rspec spec/feed_fetcher_spec.rb:42
```

Tests run with `ENV['RACK_ENV'] = 'test'`. The HTTP layer + HealthRegistry + summarizer are no-ops in test env unless explicitly opted in via env var. Stubbing pattern follows `t-money`'s `services_spec.rb` — `instance_double(Net::HTTPSuccess, body: ...)` returned by `allow(Net::HTTP).to receive(:start)`.

CI is configured at [.github/workflows/ci.yml](.github/workflows/ci.yml) — runs on push to `main` and every PR.

## Common gotchas (anticipated)

1. **Feed encoding.** RSS bodies in the wild are UTF-8, ISO-8859-1, Windows-1252, sometimes mis-declared. Force UTF-8 on parse and sanitize-or-drop invalid sequences. Test with a known-bad feed in fixtures.

2. **Atom vs RSS 2.0 vs RSS 1.0.** Don't write three parsers — pick one library (start with `feedjira`) that normalises all three to a single shape. If you fork the parser, you'll regret it.

3. **Article-content size.** Some entries are 100 KB of inline HTML. PG handles big TEXT columns fine, but don't `SELECT *` when you only need the listing fields — index-supported queries that omit `content_html` / `content_text` keep the `/articles` page fast even with thousands of rows.

4. **De-dup across feeds.** The same article appears in HN front page + the publisher's RSS. Article id is keyed by `feed_url + article_url`, so dedupe is per-article-per-feed, not global. If global dedup matters, add a separate URL-hash index.

5. **HTML sanitization in the reading view.** Strip `<script>`, `<iframe>`, on-* event handlers. `loofah` or `sanitize` gem; whitelist mode, not blacklist.

6. **Cache-only render contract.** Same as t-money — `/articles` and `/dashboard` MUST NOT fetch feeds. The hard test will live in `spec/articles_perf_spec.rb` and assert `FeedFetcher` is never called during render.

7. **Summarizer cache.** LLM summaries are EXPENSIVE and should be permanent for a given article id. Don't invalidate them on feed re-fetch — only on explicit user "re-summarize" action.

8. **Conditional-GET freshness.** `If-Modified-Since` honours feed-publisher clocks, which can be wrong. Always also check the parsed feed's most-recent entry date — if it's newer than what we have, accept the feed even when the server returned 200 with stale headers.

## Deploy pipeline

`make deploy-patch` (or `release-minor` / `release-major`) is the one command to ship:

1. Gates: clean tree, on `main`, full RSpec suite green.
2. Bumps `VERSION`, commits `chore: release vX.Y.Z`, tags, pushes commit + tag to origin.
3. GitHub Actions picks up the `v*` tag → runs the **deploy workflow** (`.github/workflows/deploy.yml`):
   - **test job** — full RSpec suite in CI (same as `ci.yml`) — deploy is cancelled if this fails.
   - **deploy job** (`needs: test`) — builds `linux/amd64` Docker image via `buildx`, pushes `:X.Y.Z` + `:latest` to DOCR, SSHs to the Droplet and runs `make deploy` (git pull + image pull + `docker compose up --force-recreate`).
4. Agent watches with `gh run watch` and reports when live.

**Secrets required** (set in GitHub repo Settings → Secrets → Actions):

| Secret | Value |
|---|---|
| `DIGITALOCEAN_ACCESS_TOKEN` | DO API token for DOCR login |
| `DEPLOY_SSH_KEY` | Private key for `deploy@<droplet-ip>` (`~/.ssh/id_rsa`) |
| `DROPLET_IP` | the Droplet's public IP (resolve with `terraform output -raw droplet_ipv4`) |

**Rollback**: set `IMAGE_TAG=X.Y.Z` in `/opt/app/.env` on the Droplet, then `make deploy` there.

**Manual fallback** if GH Actions is down: `make publish-image && make _remote_deploy DROPLET_IP=<droplet-ip>`.

## AJAX pattern

Many interactive elements use in-place AJAX to avoid full-page reloads (which scroll back to top on long pages). The convention:

1. **Route** — add a `wants_json?` branch that returns `content_type :json` + a hash with `ok:` and relevant fields. The redirect/HTML branch stays for no-JS fallback.
2. **Form** — add a `js-*` class (e.g. `js-mute-add`, `js-catalog-add`) so the JS handler can identify it via `e.target.closest('form.js-*')`.
3. **JS handler** — listen on `document` with event delegation (not per-element), `e.preventDefault()`, `fetch(url, { headers: { Accept: 'application/json' } })`, update DOM in place, show flash via `document.getElementById('flash-mount')`.

**Existing AJAX surfaces** (do not accidentally convert back to full reload):

| Surface | JS file | Class hook |
|---|---|---|
| Feeds: add/remove/weight/refresh | `feeds.js` | `js-add-feed`, `js-remove-feed`, `js-catalog-add`, `js-feed-weight-form`, `js-refresh-feed` |
| NPR / PBS subscribe | `source-page.js` | `js-catalog-add` (guarded by `.my-feeds-section` presence) |
| Sports follow/unfollow | `sports-follow.js` | `js-sports-follow-form` |
| Stock follow/unfollow | `stock-follow.js` | `js-stock-follow-form` |
| Article 👍/👎 | `article-feedback.js` | `.news-list` delegated click on `.feedback-row-btn` |
| Mutes add/delete | `mutes-tags.js` | `js-mute-add`, `js-mute-delete` |
| Tags add/delete | `mutes-tags.js` | `js-tag-add`, `js-tag-delete` |

## Sidekiq cron schedule

Managed via `config/sidekiq_cron.yml`, loaded at Sidekiq boot. View registered jobs at `/admin/sidekiq/cron`. Force-run buttons for key jobs live on `/admin/status`.

| Job name | Cron | Worker | Purpose |
|---|---|---|---|
| `refresh_all_feeds` | `0 * * * *` | `RefreshAllFeedsWorker` | Hourly fan-out: enqueue `FeedRefreshWorker` per subscribed feed |
| `sports_sync` | `30 * * * *` | `SportsSyncWorker` | Hourly :30 — ESPN match schedules + standings + rankings |
| `stock_sync` | `*/15 * * * *` | `StockSyncWorker` | Every 15 min — refresh cached quotes for followed stock symbols |
| `index_sync` | `5 * * * *` | `IndexSyncWorker` | Hourly :05 — refresh 10 major world indices (ETF proxies via Yahoo Finance + Finnhub) |
| `generate_sudoku` | `0 1 * * *` | `GenerateSudokuWorker` | Daily 01:00 UTC — pre-generate next 7 days of puzzles |
| `generate_trivia` | `30 1 * * *` | `GenerateTriviaWorker` | Daily 01:30 UTC — generate News Trivia quiz from last 24h articles |
| `fix_article_links` | `45 4 * * *` | `FixArticleLinksWorker` | Daily 04:45 UTC — re-scrub articles with `content_scrubbed = FALSE` |

## UX and design philosophy

These principles apply to every new feature and are load-bearing for the product's feel:

- **Apple-style UI** — clean typography, generous whitespace, progressive disclosure. New features should feel like they were always there, not bolted on.
- **Never drown users in choice** — as the catalog grows, surface what's relevant. The `/feeds` filter bar shows only topics the user has subscribed to. Onboarding chips auto-populate from `FeedCatalog::TOPICS` so adding a topic is one place. Catalog chips in the browse bar auto-enumerate topics — no hardcoded lists to update.
- **Personalization over completeness** — the right 5 results > an exhaustive 50. Recommendation, triage, For You ranking, and the topic filter bar all serve this.
- **Scroll position is precious** — on long pages (`/articles`, `/feeds`, `/stocks`) a full-page reload after a button tap is a bad experience. Convert actions to AJAX (see AJAX pattern above). If a new interactive element would cause a full-page reload on a long page, it needs an AJAX path.
- **User's content comes first** — on every content page (Podcasts, Comics, Radio, etc.) the user's own subscriptions and recent items render above discovery/catalog sections. "Recent episodes" before "Subscribed shows"; "My Stations" before "Recommended for you".

## Documentation files

- [SPEC.md](SPEC.md) — project brief (frozen)
- **[AGENTS.md](AGENTS.md)** — this file (developer/agent reference). Project-specific *architecture* (what the codebase looks like, conventions, gotchas).
- **[CLAUDE.md](CLAUDE.md)** — general LLM-coding *behaviour* (think before coding, simplicity first, surgical changes, goal-driven execution). Read this alongside AGENTS.md when picking up work; the two are complementary, not overlapping. CLAUDE.md is what to do; AGENTS.md is what's where.
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — PR workflow (branch / commit style / tests / CI / merge)
- [DEVELOPER.md](DEVELOPER.md) — pointer to AGENTS.md (kept for legacy reference)
- README.md — user-facing overview (status note + page list, kept current per PR)
- [TODO.md](TODO.md) — informal scratch list of UI / UX ideas the user wants to discuss before implementing. Not a roadmap (that's still SPEC.md's tier list); read it when the user references items by section heading.
- [STUFF.md](STUFF.md) — random user-facing asks. Tracks request lifecycle from "captured" → "done" with a short note. The live-updates rule above applies: every PR that ships work captured here flips the relevant item in the same change.

**Workflow rule**: every PR that changes behaviour should update the relevant docs in the same PR — see [CONTRIBUTING.md](CONTRIBUTING.md) and the workflow rule inherited from `t-money`'s memory layer.
