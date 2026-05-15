# Tech Feed Reader

A multi-user, passkey-authenticated web application that aggregates public, free RSS / Atom feeds for technology articles, sports news + scores, nature/YouTube channels, and podcasts. Reading, tagging, search, summarization, AI-assisted triage, and personalised relevance ranking. Conventions inherited from [t-money-terminal](https://github.com/outten/t-money-terminal) — Ruby / Sinatra / ERB / RSpec, cache-only render contract, scheduled background refresh — but storage is SQLite (single `data/app.db`, FTS5 for search) instead of `t-money`'s file-per-store JSON.

> **Status: multi-user behind a passkey auth wall; covers tech + sports + nature/YouTube + podcasts; ranked + triaged + summarized; popular-with-other-readers discovery on /feeds.** Auth (Phase A1) ships passkey-only sign-up + sign-in with 10 single-use recovery codes, an auth-wall middleware on every protected route, and `/account` for managing display name + passkeys + recovery-code regeneration + account deletion. Per-user data split (Phase A2) gives every signed-in user their own `read_state` / bookmarks / tags / mute rules / sports follows / digests / triages; the `feeds` catalog stays shared via a `user_feed_subscriptions` bridge so one fetch keeps every subscriber up to date. Add feeds from a curated catalog of 79 entries on `/feeds` (recommended-for-you + 🔥 popular-with-other-readers top charts + a client-side filter toolbar with search + topic chips on every list); Apple Podcasts URLs auto-resolve to the underlying RSS; an AI feed recommender (Claude) suggests catalog picks from a free-text prompt. The home `/` shows the marketing pitch to first-time visitors and **What's On Today** (today's sports fixtures for followed teams, top reads ranked by the For You scorer, podcast episodes, and YouTube videos) to returning users. `/articles` is the unified reading list with day-group dividers, left-anchored thumbnails (per-article → YouTube → feed-cover fallback), source-cluster ribbons, and a 📖 reading-time pill. `/triage` runs an AI triage (Claude Sonnet 4.6) that classifies your unread queue into must-read / optional / skip with rationale; daily cron emits a triage per topic. `/sports` covers scores / standings / iCal calendar / per-team detail / tennis rankings with follows + "articles mentioning Sinner" surfaces. `/podcasts` groups subscribed shows; a persistent mini-player at the bottom of every page keeps audio playing across navigation, with resume-where-you-left-off + a 🚌 bus-mode chip for sub-15-min commute episodes. `/youtube` lists subscribed channels with a bulk-add textarea that resolves `@PBSNewsHour`-style handles → canonical channel-feed URLs via a single channel-page scrape and kicks off a background fetch so new channels populate within ~30s. `/topics` clusters across the recent corpus using a weighted-scoring tokenizer (publisher categories 2× body keywords, proper-noun phrase detection like "Jannik Sinner", ubiquity ceiling, URL/site-boilerplate stopword sweep). `/search` is FTS5 with snippet highlighting, kind-icon results, and pre-search suggestion chips. Observability ships `/health` (liveness JSON), `/metrics` (Prometheus), `/admin/dashboard` (article counts + 7-day Activity chart), and `/admin/traces` (OpenTelemetry). CLI: `make refresh-feed FEED=<id-or-url>`, `make refresh-feeds`, `make scheduler`, `make digest`, `make triage`, `make sync-sports`, `make run-all` / `make stop-all`.

## Getting started

```bash
make install
make seed-feeds # optional: insert the 5 starter feeds (browse 79 more on /feeds)
make run        # dev server with rerun auto-reload → http://localhost:4567
make test       # RSpec — smoke suite passes out of the box
```

Runs on Ruby 3.4.1 (`.ruby-version` pinned). No API keys required to boot — Anthropic API key (for Tier 2 LLM summaries) is the only one wired and is optional.

## Pages

| Page | URL | What it shows |
|---|---|---|
| Home | `/` | Marketing pitch for first-time visitors; **What's On Today** (sports / read / listen / watch) for returning users. Continue-progress tile when any podcast or YouTube video has a saved position |
| About | `/about` | Philosophy, anti-swivel-chair argument, how-it-works, tech stack |
| Articles | `/articles` | Unified reading list (📄 articles + 🎧 podcasts + 📺 videos). Day-group dividers, left-anchored thumbnails, source-cluster ribbons, 📖 reading-time pill, For You sort, topic chips, skim mode |
| Article | `/article/:uid` | Single article + cached summary + Read-next. Podcasts get a "Play episode" affordance; YouTube articles embed the player with watch-progress + resume |
| Topics | `/topics` | Trending term clusters with sample articles; 7/14/30-day window selector |
| Topic detail | `/topics/:term` | Synthesized "highlights" + every article in the cluster, summaries inline |
| Podcasts | `/podcasts` | Subscribed shows grouped freshest-first + recent episodes |
| YouTube | `/youtube` | Subscribed YouTube channels grid + "+ Add channels" bulk-textarea (resolves @handles via channel-page scrape) |
| YouTube channel | `/youtube/:feed_id` | 10 most recent videos for one subscribed channel as 16:9 tiles |
| Sports | `/sports` | Followed-team score tiles + per-sport landings (NFL / NBA / soccer / rugby / tennis). Calendar + standings + per-team detail + tennis player follows nested below |
| Sports calendar | `/sports/calendar` | Upcoming fixtures across followed teams + iCal export |
| Triage | `/triage` | AI triage (Claude Sonnet 4.6) — classifies unread into must-read / optional / skip with rationale; per-topic chips; daily cron history |
| Digests | `/digests` | Daily snapshots of unread articles + summaries (produced by `make digest`) |
| Digest detail | `/digests/:id` | Inline render of a stored digest + opt-in "Summarize with Claude" |
| Feeds | `/feeds` | Manage RSS subscriptions; ✨ AI feed recommender (Claude) + "Recommended for you" + 🔥 Popular-with-other-readers top charts + client-side filter toolbar (search + topic chips) + full 79-entry catalog. Apple Podcasts URLs auto-resolve to RSS |
| Tags | `/tags` | User-defined tag rules + activity |
| Search | `/search` | FTS5 search across article history; pre-search suggestion chips, card-style results with snippet highlighting |
| Bus mode | `/bus` | Podcast episodes ≤15 min — pick something for the commute |
| Sign up | `/sign-up` | Passkey registration ceremony; receive 10 single-use recovery codes (shown once) |
| Sign in | `/sign-in` | Passkey authentication; "Use a recovery code" fallback |
| Account | `/account` | Manage display name, list / add / revoke passkeys, regenerate recovery codes, delete account (typed-confirmation gate) |
| Admin | `/admin` | System overview, integration status, sub-page links |
| Admin dashboard | `/admin/dashboard` | Article counts, 7-day Activity chart, top feeds + tags |
| Cache admin | `/admin/cache` | Per-feed cache age + manual refresh |
| Provider health | `/admin/health` | Per-feed fetch health |
| Backgrounds | `/admin/backgrounds` | Page-background image pool (refreshes 100 random IDs from Picsum) |
| Traces | `/admin/traces` | Recent OpenTelemetry spans (in-memory ring buffer) |
| Health (JSON) | `/health` | Liveness probe + dependency checks |
| Metrics | `/metrics` | Prometheus exposition format |

## Documentation

- **[SPEC.md](SPEC.md)** — project brief: goals, non-goals, data model, page list, roadmap.
- **[AGENTS.md](AGENTS.md)** — architecture, caching contract, store inventory, common gotchas.
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — PR workflow (branch / commit / tests / CI / merge).
- **[DEVELOPER.md](DEVELOPER.md)** — pointer doc for new contributors.

## Conventions inherited from `t-money-terminal`

Branch naming `outten/TODO-NNN`, single-commit-per-PR, rebase-merge, `make test` is gating, docs updated in the same PR as the behaviour change, review-before-shipping. Full workflow in [CONTRIBUTING.md](CONTRIBUTING.md).
