# Tech Feed Reader — SPEC

> Working name. Rename to taste before seeding the new git repo.

## One-liner

A single-user web application that aggregates public, free RSS / Atom feeds for technology articles, with reading, tagging, search, and summarization tooling. Conventions inherited from `t-money-terminal` (Ruby / Sinatra / ERB / RSpec, cache-only render contract, scheduled background refresh) but storage is SQLite (single `data/app.db`, FTS5 for search) instead of `t-money`'s file-per-store JSON.

## Goals

1. **Aggregate** — subscribe to N RSS / Atom feeds; one combined article stream sorted by recency.
2. **Read** — distraction-free per-article reading view with the publisher's full content where the feed provides it; readable extraction where it doesn't.
3. **Analyze** — tagging (rule-based + manual), filter/search, per-feed and per-tag activity over time.
4. **Summarize** — short summaries per article (extractive first, LLM-backed second), cached so re-renders are free.

The user is one person reading ~50–200 articles a week across ~20–50 feeds. No accounts. No social features. No paid feeds.

## Non-goals

- Multi-user / authentication / accounts.
- Paid / authenticated feeds (Substack-paywalled, NYT-subscriber, etc.).
- Mobile-native app — responsive web only.
- Real-time push (websockets, server-sent events). Polling is fine.
- Comments / annotations / sharing.
- Recommendation engine ("you might like..."). Out of scope for v1.

## Architecture (target)

Same shape as `t-money-terminal` — see [AGENTS.md](AGENTS.md) for the full pattern. Quick summary:

- **Ruby 3.4+ / Sinatra / ERB / RSpec / rerun** (auto-reload dev loop).
- **Single SQLite DB** at `data/app.db` (WAL mode, `foreign_keys=ON`) holds feeds, articles, read state, tags, and summaries. FTS5 backs `/search`. The file-per-store JSON pattern from `t-money` is replaced — SQLite provides atomicity, transactions, and full-text search out of the box.
- **Cache-only render contract**: `/dashboard` and `/articles` render purely from the DB. The only network events are the background scheduler, the `/admin/refresh/*` buttons, and explicit user-triggered fetches.
- **Per-feed TTL** (analogous to `t-money`'s market-aware TTL): the scheduler picks feed-fetch cadence per feed based on observed update frequency. High-volume feeds (HN, Lobsters) poll every 15 min; low-volume blogs every 4–6 h.
- **HealthRegistry** pattern for feed-fetch observability — bounded ring buffer of `(feed, timestamp, status, latency)` tuples surfaced at `/admin/health`.
- **`UserAgent` + retry/backoff layer** — single shared HTTP client with cache-friendly headers (`If-Modified-Since`, `If-None-Match`) so feeds that support 304 don't waste bandwidth.

## Data model

### Tables (SQLite — `data/app.db`)

| Table | Purpose |
|---|---|
| `feeds` | Subscribed feeds: url, title, fetch_interval_seconds, last_fetched_at, last_etag, last_modified, last_status |
| `articles` | Article history: id (rowid), uid (SHA1 slug), feed_id, title, url, author, published_at, content_html, content_text |
| `articles_fts` | FTS5 virtual table over `articles(title, content_text)`; kept in sync via triggers |
| `read_state` | Per-article state: read, bookmarked, archived, opened_at — keyed by article rowid |
| `tags` | User-defined tag rules: name, match_kind (regex/keyword/feed_id), match_value |
| `article_tags` | Many-to-many join between articles and tags |
| `summaries` | Extractive + LLM summaries per article; immutable (re-summarize on demand) |
| `schema_migrations` | Migration runner state — see `db/migrations/*.sql` |

`HealthRegistry` lives in process memory only (bounded ring buffer of feed-fetch observations); it clears on restart.

Schema is defined in [db/migrations/001_init.sql](db/migrations/001_init.sql); the runner is [app/database.rb](app/database.rb).

### Article id

Each article has both a SQLite rowid (`articles.id`, used internally for joins and FTS5 linkage) and a stable `uid` = `SHA1(feed_url + article_url)[0,12]` used in URLs (`/article/abc123def456`). The uid is stable across re-fetches; the rowid is internal.

## Pages (initial set)

| Page | URL | What it shows |
|---|---|---|
| Dashboard | `/dashboard` | Recent unread (top 20) · top tags this week · feed-health banner · search box |
| Articles | `/articles` | Main reading interface: paginated, filterable by tag / feed / read-state |
| Article | `/article/:id` | Full reading view: title · publisher · published_at · content · cached summary · tag chips |
| Feeds | `/feeds` | Manage feeds: add (paste URL → fetch + parse) · remove · per-feed stats |
| Tags | `/tags` | Manage tag rules · activity per tag |
| Search | `/search?q=...` | Full-text search across `content_text` + title + summary |
| Cache admin | `/admin/cache` | Per-feed cache age · refresh-one button · refresh-all button |
| Provider health | `/admin/health` | Feed-fetch success / latency / errors per feed |

## Caching contract

The same hard rule that makes `/portfolio` fast in `t-money` applies here:

```
Page renders MUST be cache-only.
  /dashboard → reads articles + read_state + summaries from SQLite — no fetches
  /articles  → same
  /article/:id → same; summarize button is the only on-demand network event
                  on this page

Network events ONLY happen via:
  - Scheduled poll (make scheduler)
  - Explicit /admin/refresh/{feed,all} button
  - Adding a new feed (one-shot fetch + parse)
  - User clicking "summarize" on /article/:id (LLM call)
```

Hard test in `spec/articles_perf_spec.rb` (mirroring `portfolio_perf_spec.rb`) asserting `not_to receive(:fetch_feed)` on `/articles` render.

## Roadmap (Tier 1 / 2 / 3, mirrors `t-money` cadence)

### Tier 1 — get reading [P0]

- A. `FeedsStore` + add/remove via `/feeds`.
- B. RSS / Atom parser (Ruby's `rss` stdlib or `feedjira`); writes `ArticlesStore`.
- C. Background scheduler script (`scripts/scheduler.rb`) honouring per-feed intervals + `If-Modified-Since` / `ETag`.
- D. `/articles` reading view: list, filter by feed / tag, mark read.
- E. `/article/:id` single-article view (publisher's content).
- F. `ReadStateStore` (read / bookmarked / archived).
- G. CI workflow + RSpec scaffold.

### Tier 2 — analyze + summarize [P1]

- H. Tagging: rule-based (`tags` + `article_tags`) + manual override on the article view.
- I. Full-text search across `content_text` + title (SQLite FTS5 — index already in place); widen to summaries when those land.
- J. Extractive summary (TextRank-style; pure Ruby) cached per article.
- K. LLM-backed summary as an opt-in upgrade (Claude API; cached forever per article id).
- L. Per-tag / per-feed activity charts on `/dashboard` (Chart.js, mirroring t-money's value-over-time pattern).

### Tier 3 — quality of life [P2]

- M. Topic-clustering across recent articles (term overlap; cheap pure-Ruby first pass).
- N. Export: per-tag or per-feed dump as Markdown / JSON / OPML.
- O. Recommendation: "articles like this one" via term overlap. Validate against the no-recommendation-engine non-goal — keep it deterministic, not personalized.
- P. Public OPML import for bulk feed seeding.

## Out of scope / dropped (recorded so the choice is visible)

- **Multi-user** — single-user personal tool, like `t-money`.
- **Hosted LLM APIs other than Claude** — keep one provider for summarization; Claude API only.
- **Comments / replies** — not the use case.
- **Real-time push** — polling is fine, web app refresh on click.
- **Crypto / financial-data integration** — that's `t-money`'s job.

## Conventions inherited from `t-money-terminal`

- **Branch naming**: `outten/TODO-NNN`.
- **Commit style** + **PR body template** + **rebase merge** workflow — see [CONTRIBUTING.md](CONTRIBUTING.md).
- **Update relevant docs in every PR** — see CONTRIBUTING.md and the project memory rule.
- **Review before shipping** — pause for explicit user go-ahead before commit / push / PR / merge.
- **GitHub Actions CI** runs RSpec + scripts syntax check on every PR.
- **`.credentials` for keys** (Claude API key for summarization, none other expected at v1).

## Resolved at v1 kickoff

These were the four open questions surfaced before any feature code landed; recording the answers here so the rationale is visible.

1. **Initial seed feed list** — start with 5 to validate the pipeline: Hacker News, Lobsters, Ars Technica, The Verge, Simon Willison's blog. More added via `/feeds` once the UI lands.
2. **Summary backend** — extractive first (no API key needed), Claude API wired in Tier 2 alongside it. Both gated behind a user button on `/article/:id`.
3. **Storage shape for articles** — **SQLite from day 1** (replaces monthly-sharded JSON). FTS5 backs `/search` and removes a Tier 2 design choice. WAL + foreign-key cascades cover the concurrency + integrity story.
4. **Mobile** — desktop-first; responsive CSS is welcome but mobile-native is a non-goal.
