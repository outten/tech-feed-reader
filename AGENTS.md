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
make run                     # auto-reload via rerun → http://localhost:4567 (alias: make dev)
make serve                   # one-shot run, no auto-reload
make test                    # RSpec
make refresh-feeds           # poll every feed in FeedsStore once
make refresh-feed FEED=...   # poll one feed by URL or id
make scheduler               # long-running poller honouring per-feed intervals
make summarize ARTICLE=...   # one-off summarize (CLI; mirrors the on-page button)
```

`make run` reads [.rerun](.rerun) for watch dirs and ignore globs. **`.rerun` does NOT support `#` comments** — its contents are shell-split verbatim. Keep it option-only.

## Caching architecture

**Two-tier in-memory cache** (mirroring `t-money`'s `MarketDataService`):
- `@cache` — live; gated by per-feed `effective_ttl`.
- `@persistent_cache` — fallback; survives `bust_cache!`. Returned when live is empty.
- `@cache_timestamps` — per-feed timestamp.

**Disk cache** at `data/cache/`:
```
data/cache/
├── feeds/<feed_id>.xml         # raw RSS/Atom payload (last successful fetch)
├── articles/<yyyy-mm>.json     # monthly-sharded article history (full content extracted at fetch)
├── summaries/<article_id>.json # extractive + LLM summaries, immutable per article id
└── feed_meta.json              # per-feed last_etag / last_modified / last_fetched_at
```

**Per-feed TTL** (analogous to `t-money`'s market-aware TTL):

| Feed cadence | Default poll interval |
|---|---|
| High-frequency (HN, Lobsters, /r/programming) | 15 min |
| Major publishers (Ars, Verge, NYT-tech, …) | 1 h |
| Personal blogs / low-volume | 4–6 h |

Override per feed in `FeedsStore` — the value is the source of truth, the table above is just the suggested default at add-time.

**Rendering contract** (load-bearing — break it and pages get slow):

```
Page renders MUST be cache-only.
  /dashboard, /articles, /article/:id → ArticlesStore + SummaryStore + ReadStateStore reads only

Network events ONLY happen via:
  - Scheduled poll (make scheduler)
  - Admin refresh (POST /admin/refresh/{feed,all})
  - Adding a new feed (POST /feeds)
  - User-initiated summarize on /article/:id (Claude API call)
```

Hard test will live in `spec/articles_perf_spec.rb` (mirrors `t-money`'s `portfolio_perf_spec.rb`) asserting `not_to receive(:fetch_feed)` on `/articles` and `/dashboard` render.

## Stores (file-backed, mutex-guarded, atomic-rename writes)

| Store | File | Purpose |
|---|---|---|
| `FeedsStore` | `data/feeds.json` | Subscribed feeds: id, url, title, fetch_interval_seconds, last_fetched_at, last_etag, last_modified, last_status |
| `ArticlesStore` | `data/articles/<yyyy-mm>.json` | Article history sharded by published-month: id, feed_id, title, url, author, published_at, content_html, content_text, tags |
| `TagsStore` | `data/tags.json` | User tag rules: name, match (regex / keyword list / feed_id) |
| `ReadStateStore` | `data/read_state.json` | Per-article state: read, bookmarked, archived, opened_at |
| `SummaryStore` | `data/summaries/<article_id>.json` | Cached summaries — extractive always; LLM only when user clicks "summarize" |
| `HealthRegistry` (in-memory) | — | Bounded ring buffer of feed-fetch observations; surfaces at `/admin/health` |

All mutating stores use `MUTEX.synchronize` + write-to-`.tmp`-then-rename — same as `t-money`'s `PortfolioStore` / `TradesStore` / `ProfileStore`.

## Article id

`SHA1(feed_url + article_url)[0,12]`. Stable across re-fetches, URL-safe, short enough for a clean route segment (`/article/abc123def456`).

## Feed-fetch flow

```
1. read FeedsStore[feed_id]
2. GET feed_url with If-Modified-Since: feed[:last_modified] and If-None-Match: feed[:last_etag]
3. if 304 → record health observation, update last_fetched_at, return
4. if 200 → parse with feedjira (or rss stdlib), extract entries
5. for each entry not already in ArticlesStore (by article_id):
     - run readability extraction on entry[:content] (single shared extractor)
     - assign tags (TagsStore rules)
     - write to ArticlesStore[<yyyy-mm>]
6. update FeedsStore[feed_id] with new etag / last_modified / last_fetched_at / last_status
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
  main.rb                  # Sinatra routes
  feed_fetcher.rb          # HTTP layer (If-Modified-Since / ETag honouring) + parse
  feed_parser.rb           # rss / feedjira wrapper; normalises Atom + RSS to one shape
  providers/
    readability.rb         # extract main content from origin URL
    archive.rb             # archive.org fallback
    http_client.rb         # shared user-agent + retry/backoff + cache headers
  feeds_store.rb
  articles_store.rb        # monthly-sharded
  tags_store.rb
  read_state_store.rb
  summary_store.rb
  summarizer/
    extractive.rb          # TextRank-style; pure Ruby
    claude.rb              # Anthropic SDK wrapper
  health_registry.rb
views/                     # ERB templates — mirror t-money's UI patterns
public/
  style.css                # ported from t-money for visual consistency (TBD)
  app.js                   # search box + tag-filter behaviour
scripts/
  scheduler.rb             # long-running poller; reads FeedsStore, honours per-feed TTL
  refresh_feed.rb          # one-shot poll
  refresh_all.rb           # poll every feed once
spec/                      # RSpec
data/                      # all app state (git-ignored)
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

3. **Article-content size.** Some entries are 100 KB of inline HTML. Don't keep that in memory longer than you have to. Sharding `ArticlesStore` by month keeps the per-shard size bounded.

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
