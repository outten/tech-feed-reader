# Agent Instructions — Tech Feed Reader

> **Status: greenfield seed.** This file describes the *target* architecture and conventions inherited from `t-money-terminal`. Update it as code lands so it stays a current-state reference, not a planning document.

Operational reference for agents (and humans) working in this repo. The user-facing brief lives in [SPEC.md](SPEC.md); this file focuses on architecture, gotchas, and conventions that aren't obvious from a quick code read.

## Setup & credentials

Credentials live in `.credentials` (NOT `.env`). Both files are auto-loaded by Dotenv but `.credentials` is canonical.

```ruby
# app/main.rb
Dotenv.load(File.expand_path('../../.credentials', __FILE__))
```

**Wired keys at v1**:
- `ANTHROPIC_API_KEY` — Claude API for LLM-backed summarization (Tier 2). Optional at startup; the app degrades gracefully and falls back to the extractive summarizer.

No other API keys required — RSS / Atom feeds are public and unauthenticated. **Never commit `.credentials` or `.env`** — both are git-ignored.

## Development commands

```bash
make install                 # bundle install
make migrate                 # apply any pending db/migrations/*.sql (idempotent)
make seed-feeds              # insert the 5 v1-kickoff starter feeds (idempotent)
make run                     # auto-reload via rerun → http://localhost:4567 (alias: make dev)
make serve                   # one-shot run, no auto-reload
make test                    # RSpec
make refresh-feeds           # poll every feed in FeedsStore once
make refresh-feed FEED=...   # poll one feed by URL or id
make scheduler               # long-running poller honouring per-feed intervals
make summarize ARTICLE=...   # one-off summarize (CLI; mirrors the on-page button)
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
| `articles` | Article history: rowid (`id`), uid (SHA1 slug), feed_id, title, url, author, published_at, content_html, content_text |
| `articles_fts` | FTS5 virtual table over `articles(title, content_text)`; kept in sync via INSERT/UPDATE/DELETE triggers |
| `read_state` | Per-article state: read, bookmarked, archived, opened_at |
| `tags` | User tag rules: name, match_kind (regex/keyword/feed_id), match_value |
| `article_tags` | Many-to-many join between articles and tags |
| `summaries` | Cached summaries: extractive (always) + llm (on demand) |
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

## Project structure (target)

```
app/
  main.rb                  # Sinatra routes; auto-migrates on boot
  database.rb              # SQLite handle + migration runner
  feed_fetcher.rb          # orchestrator: conditional GET → parse → update FeedsStore
  feed_parser.rb           # feedjira wrapper; normalises RSS 2.0 / RSS 1.0 / Atom
  sanitizer.rb             # loofah whitelist; sanitize_html + text_only
  providers/
    http_client.rb         # shared user-agent + retry/backoff + scheme guard
    readability.rb         # extract main content from origin URL (Tier 2)
    archive.rb             # archive.org fallback (Tier 2)
  feeds_store.rb           # SQLite-backed wrapper (CRUD on the feeds table)
  articles_store.rb        # SQLite-backed wrapper (CRUD on articles + FTS5)
  tags_store.rb
  read_state_store.rb
  summary_store.rb
  summarizer/
    extractive.rb          # TextRank-style; pure Ruby
    claude.rb              # Anthropic SDK wrapper
  health_registry.rb
db/
  migrations/
    001_init.sql           # initial schema; new files added per feature PR
views/                     # ERB templates — mirror t-money's UI patterns
public/
  style.css                # ported from t-money for visual consistency
  app.js                   # search box + tag-filter behaviour
scripts/
  migrate.rb               # one-shot migration runner (also auto-run on web boot)
  scheduler.rb             # long-running poller; reads feeds table, honours per-feed TTL
  refresh_feed.rb          # one-shot poll
  refresh_all.rb           # poll every feed once
spec/                      # RSpec
data/                      # SQLite DB + raw-feed cache (git-ignored)
.github/workflows/ci.yml   # RSpec + scripts syntax check on push to main + every PR
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
- README.md — user-facing overview (TBD as features ship)
- TODO.md — roadmap (TBD; mirrors t-money's shipped / open / dropped structure)

**Workflow rule**: every PR that changes behaviour should update the relevant docs in the same PR — see [CONTRIBUTING.md](CONTRIBUTING.md) and the workflow rule inherited from `t-money`'s memory layer.
