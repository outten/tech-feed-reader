# Tech Feed Reader — SPEC

> Working name. Rename to taste before seeding the new git repo.

## One-liner

A single-user web application that aggregates public, free RSS / Atom feeds for technology articles, with reading, tagging, search, and summarization tooling. Same architecture and conventions as `t-money-terminal`: Ruby / Sinatra / ERB / RSpec, file-backed JSON stores, cache-only render contract, scheduled background refresh.

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
- **File-backed JSON stores** under `data/`, each guarded by `MUTEX.synchronize` + write-to-`.tmp`-then-rename for crash safety.
- **Cache-only render contract**: `/dashboard` and `/articles` render purely from cache. The only network events are the background scheduler, the `/admin/refresh/*` buttons, and explicit user-triggered fetches.
- **Per-feed TTL** (analogous to `t-money`'s market-aware TTL): the scheduler picks feed-fetch cadence per feed based on observed update frequency. High-volume feeds (HN, Lobsters) poll every 15 min; low-volume blogs every 4–6 h.
- **HealthRegistry** pattern for feed-fetch observability — bounded ring buffer of `(feed, timestamp, status, latency)` tuples surfaced at `/admin/health`.
- **`UserAgent` + retry/backoff layer** — single shared HTTP client with cache-friendly headers (`If-Modified-Since`, `If-None-Match`) so feeds that support 304 don't waste bandwidth.

## Data model

### Stores (file-backed, mutex-guarded)

| Store | File | Purpose |
|---|---|---|
| `FeedsStore` | `data/feeds.json` | Subscribed feeds: URL, title, fetch interval, last_fetched_at, last_etag, last_modified, fetch_status |
| `ArticlesStore` | `data/articles/<yyyy-mm>.json` (sharded by month) | Article history: id, feed_id, title, url, author, published_at, summary, content_html, content_text, tags |
| `TagsStore` | `data/tags.json` | User-defined tag rules: name, match (regex / keyword list / feed_id) |
| `ReadStateStore` | `data/read_state.json` | Per-article state: read, bookmarked, archived, opened_at |
| `SummaryStore` | `data/summaries/<article_id>.json` | LLM / extractive summaries keyed by article id; immutable (re-summarize on demand only) |
| `HealthRegistry` (in-memory) | — | Per-feed fetch observations; clears on restart |

### Article id

`SHA1(feed_url + article_url)[0,12]` — stable across re-fetches; safe URL slug.

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
  /dashboard → reads ArticlesStore + ReadStateStore + SummaryStore — no fetches
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

- H. Tagging: rule-based (`TagsStore`) + manual override on the article view.
- I. Full-text search across `content_text` + title + summary. SQLite or pure-Ruby reverse-index — start simple.
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

## Open questions for v1 kickoff

1. **Initial seed feed list** — what feeds does the user want pre-loaded? (HN, Lobsters, Ars Technica, The Verge, others?)
2. **Summary backend** — start with extractive-only (no API key needed) or wire Claude API from day 1?
3. **Storage shape for articles** — start with monthly-sharded JSON files, OR jump to SQLite for full-text search? FTS would simplify Tier 2's search task significantly.
4. **Mobile-friendly** as v1 priority, or desktop-only and add responsive CSS in Tier 3?

These should be resolved before the first commit lands.
