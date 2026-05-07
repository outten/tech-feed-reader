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

1. Branch off main into `outten/TODO-NNN`. Don't push to `main` directly.
2. Implement + write tests + update docs in the same change.
3. `make test` locally → must be 0 failures.
4. **Pause.** Show the user the diff / commit message; wait for explicit approval before staging.
5. Commit, push the branch, open the PR (`gh pr create`).
6. **Wait for CI green** on the PR before claiming "shipped" — CI is at [.github/workflows/ci.yml](.github/workflows/ci.yml) and runs RSpec + script syntax check on every push to `main` and every PR.
7. **Pause.** Wait for the user to merge the PR (or to grant explicit authority to merge after green CI).
8. After merge, sync local: `git checkout main && git pull --ff-only origin main && git remote prune origin`.

**Documentation rule** — every PR that changes behaviour updates the touched docs in the same PR. The bar is "no doc reads as untrue after this PR." Concretely, when shipping a new page or module, update:
- [README.md](README.md) page table + status line
- AGENTS.md (this file) — if there's a new module / store / external integration / convention worth documenting
- [CONTRIBUTING.md](CONTRIBUTING.md) — only if the process itself changed

Don't leave docs to be reconciled later.

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

**Logging**: every HTTP request, feed fetch, refresh, Claude call, chat turn, digest run, and Sidekiq job emits a single-line JSON event to STDOUT via [`app/logger.rb`](app/logger.rb). Tune verbosity with `LOG_LEVEL=debug|info|warn|error|fatal` (default `info` in dev / production, `fatal` in test so RSpec stays clean). Pipe through `jq` for pretty-printing: `make run | jq -c`.

No other API keys required — RSS / Atom feeds are public and unauthenticated. **Never commit `.credentials` or `.env`** — both are git-ignored.

## Development commands

```bash
make install                 # bundle install
make migrate                 # apply any pending db/migrations/*.sql (idempotent)
make seed-feeds              # insert FeedCatalog::seed_defaults (5 starters; 25-entry catalog browsable on /feeds)
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

**Single SQLite DB** at `data/app.db` is the source of truth for feeds, articles, read state, tags, and summaries. WAL mode lets the scheduler write while web requests read without blocking; `PRAGMA foreign_keys=ON` cascades deletes (drop a feed → its articles + their read_state + summaries + article_tags rows go too).

This replaces `t-money-terminal`'s file-per-store + mutex + atomic-rename pattern. SQLite's transactions handle atomicity; we don't need to roll our own.

**Schema lives in [db/migrations/](db/migrations/).** The runner is [app/database.rb](app/database.rb) — `Database.migrate!` is idempotent, applies any pending migration files in filename order, and is called automatically on web-app boot (skipped under `RACK_ENV=test`). `make migrate` is the explicit one-shot entry point.

**Disk cache** at `data/cache/` (separate from the DB) holds raw fetch payloads as a debug aid:
```
data/cache/
└── feeds/<feed_id>.xml   # raw RSS/Atom payload, last successful fetch
```

Article bodies, extracted content, and summaries all live in SQLite — not on disk.

**Retention policy** — articles older than `RETENTION_DAYS` (default 7) get swept by [`Pruner`](app/pruner.rb). Bookmarked articles are always preserved regardless of age; set `PRUNE_KEEP_UNREAD=1` to also preserve unread items past the window. Cascades take care of `read_state`, `summaries`, `article_tags`, and the `articles_fts` index — one DELETE on `articles` is sufficient. Wired in two places:

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
  /dashboard, /articles, /article/:id → SQLite reads only

Network events ONLY happen via:
  - Scheduled poll (make scheduler)
  - Admin refresh (POST /admin/refresh/{feed,all})
  - Adding a new feed (POST /feeds)
  - User-initiated summarize on /article/:id (Claude API call)
```

Hard test will live in `spec/articles_perf_spec.rb` (mirrors `t-money`'s `portfolio_perf_spec.rb`) asserting `not_to receive(:fetch_feed)` on `/articles` and `/dashboard` render.

## Tables

| Table | Purpose |
|---|---|
| `feeds` | Subscribed feeds: url, title, fetch_interval_seconds, last_fetched_at, last_etag, last_modified, last_status |
| `articles` | Article history: rowid (`id`), uid (SHA1 slug), feed_id, title, url, author, published_at, content_html, content_text, audio_url, audio_mime_type, audio_duration_seconds |
| `articles_fts` | FTS5 virtual table over `articles(title, content_text)`; kept in sync via INSERT/UPDATE/DELETE triggers |
| `read_state` | Per-article state: read, bookmarked, archived, opened_at, feedback (explicit ±1, Phase 3), passive_feedback (derived from listened-%, Phase 4) |
| `feed_feedback` | Per-feed weight (Phase 3): weight REAL DEFAULT 1.0, clamped to [0.25, 3.0] by `FeedFeedbackStore` |
| `mute_rules` | Hard-hide rules (Phase 5): kind ∈ `{keyword, author, feed}`, composite PK on `(kind, value)`. Applied as a NOT EXISTS sub-query in `ArticlesStore.state_query` |

**Recommendation modules** (Phase 6): `Recommendation` is the per-article "Articles like this" surfaced on `/article/:uid` (FTS5 BM25, no personalization). `Recommendation::ForYou` ([app/recommendation/for_you.rb](app/recommendation/for_you.rb)) is the personalised relevance ranker on `/articles?sort=relevance` — blends recency × per-feed weight × ±corpus overlap. Pure compute; no background job. Empty corpus collapses to chronological so a brand-new install is unaffected. `next_after(article)` (Phase 7) returns one suggestion for the Read-next card on `/article/:uid`, falling back to the FTS5 path when the corpus is cold.

**Triage::Claude** ([app/triage/claude.rb](app/triage/claude.rb), Phase 8) — AI-assisted unread classification. Pulls up to 30 unread + 20 corpus exemplars per side, prompts Claude (Sonnet 4.6, not Opus — cost guard) for structured JSON, parses defensively (strips markdown fences, salvages JSON from prose, falls back to "skip all" on parse failure rather than 500ing). Surfaces at `/triage`; manual POST trigger only — no DB persistence v1.
| `tags` | User tag rules: name, match_kind (regex/keyword/feed_id), match_value |
| `article_tags` | Many-to-many join between articles and tags |
| `summaries` | Cached summaries: extractive (always) + llm (on demand) |
| `digests` | Stored digest snapshots produced by `make digest`: subject, text_body, html_body, generated_at, window_hours, article_count |
| `schema_migrations` | Migration runner state |

`HealthRegistry` is in-memory only (bounded ring buffer of feed-fetch observations); surfaces at `/admin/health`, clears on process restart.

Per-store wrapper classes (`FeedsStore`, `ArticlesStore`, etc.) sit on top of the DB and present a higher-level API to the app — but the data lives in SQLite, not in JSON files.

## Article id

Each article has both a SQLite rowid (`articles.id`, used internally for joins and FTS5 linkage) and a stable `uid` = `SHA1(feed_url + article_url)[0,12]` used in URLs (`/article/abc123def456`). The uid is stable across re-fetches; the rowid is internal.

## Feed-fetch flow

```
1. SELECT row from feeds WHERE id = ?
2. GET feed_url with If-Modified-Since: feed.last_modified and If-None-Match: feed.last_etag
3. if 304 → record health observation, UPDATE feeds.last_fetched_at, return
4. if 200 → parse with feedjira (or rss stdlib), extract entries
5. for each entry whose uid is not already in articles:
     - run readability extraction on entry[:content] (single shared extractor)
     - INSERT into articles (FTS5 trigger keeps articles_fts in sync)
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

[`app/tracing.rb`](app/tracing.rb) boots the OTel SDK in non-test env. Auto-instrumentation via `opentelemetry-instrumentation-all` covers Sinatra, Rack, Net::HTTP, Sidekiq, and SQLite — every HTTP request, outbound fetch, job, and SQL query becomes a span automatically. Manual spans wrap `FeedFetcher#fetch_feed` (`feed.fetch`) and the two Claude paths (`llm.summarize`, `llm.chat`).

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

## Project structure

```
app/
  main.rb                          # Sinatra routes; auto-migrates on boot
  credentials.rb                   # loads .credentials/.env; aliases CLAUDE_API_KEY → ANTHROPIC_API_KEY
  database.rb                      # SQLite handle + migration runner
  logger.rb                        # JSON-line structured logger
  version.rb                       # AppVersion::GIT_SHA + STARTED_AT (used by /health, OTel resource)
  feed_fetcher.rb                  # conditional GET → parse → update FeedsStore (wrapped in OTel feed.fetch span)
  feed_parser.rb                   # feedjira wrapper; normalises RSS 2.0 / RSS 1.0 / Atom
  feed_catalog.rb                  # curated 25-feed catalog + seed_defaults
  sanitizer.rb                     # loofah whitelist; sanitize_html + text_only
  providers/
    http_client.rb                 # shared user-agent + retry/backoff + 301/302 redirect-following
    readability.rb                 # main-content extraction (teaser-feed fallback)
  feeds_store.rb                   # CRUD on feeds
  articles_store.rb                # CRUD on articles + FTS5
  read_state_store.rb              # per-article read / bookmark / archive
  tags_store.rb                    # tag rules + many-to-many links
  tags_applier.rb                  # tag-rule matcher used at import time
  summary_store.rb                 # extractive + LLM summaries
  summarizer/
    extractive.rb                  # TextRank-style; pure Ruby
    claude.rb                      # Anthropic SDK wrapper for summaries (Opus)
  chat.rb                          # Chat::Claude — chat backend, page-context system prompt (Sonnet)
  digests.rb                       # composer for the daily-digest snapshot (text + HTML fragment)
  digest_store.rb                  # CRUD on the digests table
  recommendation.rb                # FTS5-overlap "Related" panel
  topic_clusters.rb                # /topics term-clustering across the recent window
  pruner.rb                        # retention sweep — delete articles older than RETENTION_DAYS; bookmarks always kept
  health_registry.rb               # bounded ring buffer of feed-fetch observations
  metrics.rb                       # Prometheus registry + counter / gauge / histogram defs
  metrics_middleware.rb            # Rack middleware: per-request counter + histogram
  sidekiq_metrics_middleware.rb    # mirrors metrics_middleware for Sidekiq jobs
  tracing.rb                       # OpenTelemetry SDK boot + RecorderProcessor (in-memory) + optional OTLP exporter
  scheduler.rb                     # due-feed picker + refresh_one helper
  sidekiq_boot.rb                  # worker boot file: requires credentials + tracing + workers
  sidekiq_config.rb                # Sidekiq client/server config + middleware wiring
  workers/
    feed_refresh_worker.rb         # background job that refreshes a single feed
db/
  migrations/
    001_init.sql                   # initial schema
    002_articles_audio.sql         # audio_url + audio_mime_type + audio_duration_seconds on articles
    003_digests.sql                # digests table
views/                             # ERB templates
public/
  style.css                        # all CSS lives here (light + dark)
  global-player.js                 # singleton Player + mini-player UI bindings
  chat-widget.js                   # floating chat button + panel + /chat client
  header-refresh.js                # AJAX refresh-all button
  feeds.js                         # /feeds page interactions (add feed, etc.)
scripts/
  migrate.rb                       # one-shot migration runner (web boot also auto-migrates)
  seed_feeds.rb                    # insert FeedCatalog::seed_defaults
  scheduler.rb                     # long-running poller
  refresh_feed.rb                  # poll one feed (id or URL)
  refresh_feeds.rb                 # poll every feed once
  generate_digest.rb               # compose + persist a digest (cron entry point; `make digest`)
  prune_articles.rb                # delete articles older than RETENTION_DAYS (`make prune`); bookmarks always kept
  backfill_audio.rb                # one-shot recovery: fill NULL audio_url for articles whose feed publishes enclosures
  run_all.sh / stop_all.sh         # orchestrate Jaeger + Redis + web + sidekiq for a one-command dev session
spec/                              # RSpec (test env: in-memory SQLite, no real HTTP)
data/                              # SQLite DB + raw-feed cache (git-ignored)
.github/workflows/ci.yml           # RSpec + scripts syntax check on push to main + every PR
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

3. **Article-content size.** Some entries are 100 KB of inline HTML. SQLite handles big TEXT columns fine, but don't `SELECT *` when you only need the listing fields — index-supported queries that omit `content_html` / `content_text` keep the `/articles` page fast even with thousands of rows.

4. **De-dup across feeds.** The same article appears in HN front page + the publisher's RSS. Article id is keyed by `feed_url + article_url`, so dedupe is per-article-per-feed, not global. If global dedup matters, add a separate URL-hash index.

5. **HTML sanitization in the reading view.** Strip `<script>`, `<iframe>`, on-* event handlers. `loofah` or `sanitize` gem; whitelist mode, not blacklist.

6. **Cache-only render contract.** Same as t-money — `/articles` and `/dashboard` MUST NOT fetch feeds. The hard test will live in `spec/articles_perf_spec.rb` and assert `FeedFetcher` is never called during render.

7. **Summarizer cache.** LLM summaries are EXPENSIVE and should be permanent for a given article id. Don't invalidate them on feed re-fetch — only on explicit user "re-summarize" action.

8. **Conditional-GET freshness.** `If-Modified-Since` honours feed-publisher clocks, which can be wrong. Always also check the parsed feed's most-recent entry date — if it's newer than what we have, accept the feed even when the server returned 200 with stale headers.

## Documentation files

- [SPEC.md](SPEC.md) — project brief (frozen)
- **[AGENTS.md](AGENTS.md)** — this file (developer/agent reference)
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — PR workflow (branch / commit style / tests / CI / merge)
- [DEVELOPER.md](DEVELOPER.md) — pointer to AGENTS.md (kept for legacy reference)
- README.md — user-facing overview (status note + page list, kept current per PR)
- [TODO.md](TODO.md) — informal scratch list of UI / UX ideas the user wants to discuss before implementing. Not a roadmap (that's still SPEC.md's tier list); read it when the user references items by section heading.

**Workflow rule**: every PR that changes behaviour should update the relevant docs in the same PR — see [CONTRIBUTING.md](CONTRIBUTING.md) and the workflow rule inherited from `t-money`'s memory layer.
