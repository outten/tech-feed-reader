# Tech Feed Reader — SPEC

> Working name. Rename to taste before seeding the new git repo.

## One-liner

A multi-user web application that aggregates public, free RSS / Atom feeds **across multiple categories (technology, sports, nature/YouTube, podcasts, …)**, with reading, tagging, search, summarization, and personalised relevance ranking. Conventions inherited from `t-money-terminal` (Ruby / Sinatra / ERB / RSpec, cache-only render contract, scheduled background refresh) but storage is SQLite (single `data/app.db`, FTS5 for search) instead of `t-money`'s file-per-store JSON.

> **Note on this document.** SPEC.md is the v1 brief, kept as the historical baseline so the reasoning at kickoff stays auditable. The brief below is the original (technology-only, no recommendation engine). The **Scope evolution** section that follows records every place reality has diverged — what shipped, why we changed our mind, and where to find the current backlog. Treat that section, plus [TODO.md](TODO.md), as the source of truth for what the app does today.

## Scope evolution (v1.0 → v1.x)

The sections below this one are the v1 brief as written at kickoff. Things have moved since — recording the deltas explicitly so SPEC.md doesn't read as untrue.

### Multi-category aggregation (sports broadens the surface)

The original brief was "technology articles". As of v1.x the user's interests broadened to sports — **Philadelphia Eagles, Sixers, Union; New Zealand All Blacks + Black Ferns; Tennis (ATP/WTA broadly)**. The 10-phase Sports rollout is captured in [TODO.md](TODO.md) (Sports Phases S1–S10). Architecturally:

- Existing news pipeline (RSS / Atom → `articles` → `/articles`) extends to sports news with no schema change beyond a `feeds.category` column.
- A second, **structured** schema lands alongside the article schema for sports-specific data: `sports_leagues`, `sports_teams`, `sports_matches`, `sports_players`, `sports_follows`. This is genuinely new architecture — sports has scores, standings, fixtures, and per-player tracking that don't fit the article shape.
- Two new providers — `Providers::ESPN` (NFL/NBA/MLS via reverse-engineered public endpoints) and `Providers::TheSportsDB` (rugby + tennis where ESPN doesn't reach). See TODO.md S4 for the source citations.

### Personalised relevance — the v1 non-goal we changed our mind on

The original brief lists "Recommendation engine ('you might like...'). Out of scope for v1." That's still in the **Non-goals** section below — and it is no longer true. Phases 3 / 4 / 6 / 7 / 8 shipped a complete personalisation stack:

- **Phase 3** — explicit feedback signal (`👍/👎` per article + per-feed weight). Commit `c8ba317`.
- **Phase 4** — passive feedback signal (≥80% listened ⇒ +1, <10% with >30s playback ⇒ -1 on podcasts). Commit `0684bdb`.
- **Phase 6** — `Recommendation::ForYou` ranker on `/articles?sort=relevance`, blending recency × per-feed weight × ±corpus overlap. Commit `a738901`.
- **Phase 7** — Read-next card on `/article/:uid` (For You pick + FTS5 fallback). Commit `e0cbb2c`.
- **Phase 8** — AI-assisted triage at `/triage` (Claude classifies unread into must-read / optional / skip). Commit `9763085` + persistence in `3f2ac84`.

The non-goal was right at the time (we needed to avoid premature personalisation), and the change of mind is intentional, not accidental.

### Multi-user (consumer auth + per-user data split)

The original brief was explicit: "**Single-user**, web-based." That ran its course. As of v1.x the app is multi-user behind a passkey auth wall.

- **Phase A1 (passkey auth)** — STUFF #22 pivoted from an early Microsoft Entra ID plan to **consumer-facing passkey-only** (WebAuthn) with one-time recovery codes. No email, no SMS, no password. Username is the only identity field. Auth wall middleware gates every protected route. Commits `005b607` + `a9e5032` (#88).
- **Phase A2 (per-user data split)** — migration `022_a2_per_user_data.sql` widens every user-state table's PK / unique constraint to include `user_id` with `ON DELETE CASCADE`. Tables covered: `read_state`, `feed_feedback`, `mute_rules`, `tags`, `sports_follows`, `triages`, `digests`. `feeds` itself stays a **shared catalog** so one fetch keeps every subscriber up to date — per-user subscriptions live in a new `user_feed_subscriptions` bridge. Every store method that touches user-state takes `user_id` explicitly; cross-user isolation locked by [spec/cross_user_isolation_spec.rb](spec/cross_user_isolation_spec.rb). Commits `7b1533a` (#89) + `7b7bcca` (#90).
- **`/account` page (A1 follow-up)** — display name, passkey list / + Add this device / Revoke (with lockout protection), recovery-code regeneration (one-shot reveal), and account deletion with a typed-username confirmation gate. Commit `e548857` (#97).

### Other deltas the original brief didn't anticipate

- **Podcasts as first-class** — full audio pipeline, persistent mini-player surviving Turbo navigations, podcast-specific UX (Bus mode for short commute episodes). Multiple commits ending at `4a48f1e` and `42040f4`.
- **YouTube as first-class** — top-level `/youtube` nav, subscribed-channel grid, 10-most-recent-videos drill-down, in-page embedded player on YouTube articles, watch-progress that feeds the same For You corpus that podcasts use, and (STUFF #30) a bulk `@handle` resolver that scrapes the channel page to extract `channelId` + queues a background fetch on subscribe.
- **Mute filters** (Phase 5) — keyword / author / feed hard-hide rules. Commit `4234961`.
- **AI digest summaries** — Claude summarises a daily digest, cached per row. Commit `400468e`.
- **AI feed recommender** (STUFF #23) — Claude picks from the curated catalog given a free-text prompt; validates URLs before render so no hallucinations make it to the UI.
- **Popular-with-other-readers top charts** (STUFF #24) — `/feeds` shows top-5 per type (📰 News / 🏟 Sports / 🎧 Podcasts / 📺 Nature / 🎬 YouTube) ranked by distinct subscriber count.
- **/topics quality overhaul** (STUFF #28) — URL-stripping tokenizer + expanded stopwords + publisher-supplied categories (new `articles.categories` column) + weighted scoring + ubiquity ceiling + proper-noun phrase detection (e.g. "Jannik Sinner" stays one cluster). Consolidated stopword module at [app/stopwords.rb](app/stopwords.rb).
- **Tracing + observability** — OpenTelemetry SDK, `/admin/traces`, optional OTLP exporter. Multiple commits.

### Where to read what

| Question | File |
|---|---|
| What was the original v1 vision? | rest of this file (sections below this one) |
| What has actually shipped + what's queued next? | [TODO.md](TODO.md) |
| What architectural patterns are load-bearing today? | [AGENTS.md](AGENTS.md) |
| What user-facing asks did we resolve along the way? | [STUFF.md](STUFF.md) |
| How do I work on this codebase? | [CONTRIBUTING.md](CONTRIBUTING.md) |

---

## Goals

1. **Aggregate** — subscribe to N RSS / Atom feeds; one combined article stream sorted by recency.
2. **Read** — distraction-free per-article reading view with the publisher's full content where the feed provides it; readable extraction where it doesn't.
3. **Analyze** — tagging (rule-based + manual), filter/search, per-feed and per-tag activity over time.
4. **Summarize** — short summaries per article (extractive first, LLM-backed second), cached so re-renders are free.

The user is one person reading ~50–200 articles a week across ~20–50 feeds. No accounts. No social features. No paid feeds.

## Non-goals

- ~~Multi-user / authentication / accounts.~~ **Superseded.** Phase A1 (passkey auth, recovery codes, auth wall) shipped in `a9e5032` (#88) and Phase A2 (per-user data split) in `7b1533a` (#89) + `7b7bcca` (#90). The pivot rationale and final design are in *Scope evolution* above.
- Paid / authenticated feeds (Substack-paywalled, NYT-subscriber, etc.).
- Mobile-native app — responsive web only.
- Real-time push (websockets, server-sent events). Polling is fine.
- Comments / annotations / sharing.
- ~~Recommendation engine ("you might like..."). Out of scope for v1.~~ **Superseded.** Personalised relevance ranker shipped in Phase 6 (`a738901`) and consumed by the Read-next card (Phase 7) and the AI triage (Phase 8). See the *Scope evolution* section above for why we changed our mind.

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

- ~~**Multi-user** — single-user personal tool, like `t-money`.~~ **Reversed v1.x.** Consumer passkey auth + per-user data split shipped — see Phase A1/A2 in *Scope evolution* above.
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
