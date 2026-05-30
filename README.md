# Tech Feed Reader

A multi-user, passkey-authenticated web application that aggregates public, free RSS / Atom feeds for technology articles, sports news + scores, nature/YouTube channels, podcasts, and webcomics. Reading, tagging, search, summarization, AI-assisted triage, and personalised relevance ranking. Conventions inherited from [t-money-terminal](https://github.com/outten/t-money-terminal) — Ruby / Sinatra / ERB / RSpec, cache-only render contract, scheduled background refresh — but storage is PostgreSQL (managed DO cluster, `tsvector` + `ts_rank` for search) instead of `t-money`'s file-per-store JSON.

> **Status: multi-user behind a passkey auth wall; covers tech + sports + nature/YouTube + podcasts + webcomics; ranked + triaged + summarized; popular-with-other-readers discovery on /feeds.**

## What it does

- **Multi-user, passkey-only auth** (Phase A1) — WebAuthn sign-up + sign-in with 10 single-use recovery codes; an auth-wall middleware on every protected route; `/account` for display name + passkeys + recovery-code regeneration + account deletion. No passwords, no email.
- **Per-user data, shared catalog** (Phase A2) — every signed-in user has their own `read_state` / bookmarks / tags / mute rules / sports follows / digests / triages; the `feeds` catalog stays shared via a `user_feed_subscriptions` bridge so one fetch keeps every subscriber up to date.
- **Discovery on `/feeds`** — 108 curated catalog entries with a client-side filter toolbar (search + topic chips); recommended-for-you + 🔥 popular-with-other-readers top charts; AI feed recommender (Claude) from a free-text prompt; Apple Podcasts URLs auto-resolve to the underlying RSS.
- **Home & onboarding** — `/` shows a marketing pitch to first-time visitors, the `/welcome` topic-chip onboarding (Tech / Sports / Nature / Podcasts / Humor) to newly signed-in users with zero subscriptions, and **What's On Today** (today's sports fixtures, top reads ranked by For You, podcast episodes, YouTube videos) to everyone else.
- **Unified reading list** (`/articles`) — mixes 📄 articles, 🎧 podcasts, 📺 videos with day-group dividers, left-anchored thumbnails (per-article → YouTube → feed-cover fallback), source-cluster ribbons, and a 📖 reading-time pill.
- **AI triage** (`/triage`) — Claude Sonnet 4.6 classifies your unread queue into must-read / optional / skip with rationale; daily cron emits one triage per topic.
- **Sports** (`/sports`) — followed-team score tiles, iCal calendar export, per-team detail pages, league standings, tennis rankings, and "articles mentioning Sinner"-style entity surfaces.
- **Podcasts** (`/podcasts`) — subscribed-show grid with a persistent mini-player at the bottom of every page that survives Turbo navigation; resume-where-you-left-off; 🚌 bus-mode chip for sub-15-min commute episodes.
- **YouTube** (`/youtube`) — subscribed-channel grid with a bulk-add textarea that resolves `@PBSNewsHour`-style handles → canonical channel-feed URLs via channel-page scrape; background fetch populates new channels within ~30s.
- **Comics** (`/comics`) — subscribed webcomic series tiles (latest panel as cover) + recent panels list; comic-aware article hero (no crop) + click-to-zoom image lightbox.
- **Topics & search** — `/topics` clusters across the recent corpus using weighted scoring (publisher categories 2× body keywords, proper-noun phrase detection like "Jannik Sinner", ubiquity ceiling, URL/site-boilerplate stopword sweep); `/search` is PG full-text with `tsvector` + `ts_headline` snippet highlighting and pre-search suggestion chips.
- **Observability** — `/health` (liveness JSON), `/metrics` (Prometheus), `/admin/dashboard` (article counts + 7-day Activity chart), `/admin/traces` (OpenTelemetry ring buffer).
- **CLI** — `make refresh-feed FEED=<id-or-url>`, `make refresh-feeds`, `make scheduler`, `make digest`, `make triage`, `make sync-sports`, `make run-all` / `make stop-all`.

## Getting started

```bash
make install
make seed-feeds # optional: insert the 5 starter feeds (browse 103 more on /feeds)
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
| Bookmarks | `/bookmarks` | Every article you've saved with the ☆ button, newest first; reuses /articles list affordances |
| Article | `/article/:uid` | Single article + cached summary + Read-next. Podcasts get a "Play episode" affordance; YouTube articles embed the player with watch-progress + resume |
| Topics | `/topics` | Trending term clusters with sample articles; 7/14/30-day window selector |
| Topic detail | `/topics/:term` | Synthesized "highlights" + every article in the cluster, summaries inline |
| Podcasts | `/podcasts` | Subscribed shows grouped freshest-first + recent episodes |
| YouTube | `/youtube` | Subscribed YouTube channels grid + "+ Add channels" bulk-textarea (resolves @handles via channel-page scrape) |
| YouTube channel | `/youtube/:feed_id` | 10 most recent videos for one subscribed channel as 16:9 tiles |
| Comics | `/comics` | Subscribed webcomic series tiles (latest panel as cover) + recent panels linear list |
| Comic series | `/comics/:feed_id` | 30 most recent panels for one subscribed series; click any to read in /article/:uid with comic-aware hero + lightbox |
| Sports | `/sports` | Followed-team score tiles + per-sport landings (NFL / NBA / soccer / rugby / tennis). Calendar + standings + per-team detail + tennis player follows nested below |
| Sports calendar | `/sports/calendar` | Upcoming fixtures across followed teams + iCal export |
| Triage | `/triage` | AI triage (Claude Sonnet 4.6) — classifies unread into must-read / optional / skip with rationale; per-topic chips; daily cron history |
| Digests | `/digests` | Daily snapshots of unread articles + summaries (produced by `make digest`) |
| Digest detail | `/digests/:id` | Inline render of a stored digest + opt-in "Summarize with Claude" |
| Feeds | `/feeds` | Manage RSS subscriptions; ✨ AI feed recommender (Claude) + "Recommended for you" + 🔥 Popular-with-other-readers top charts + client-side filter toolbar (search + topic chips) + full 79-entry catalog. Apple Podcasts URLs auto-resolve to RSS |
| Tags | `/tags` | User-defined tag rules + activity |
| Search | `/search` | Full-text search across article history (PG `tsvector` + `ts_headline`); pre-search suggestion chips, card-style results with snippet highlighting |
| Bus mode | `/bus` | Podcast episodes ≤15 min — pick something for the commute |
| Sign up | `/sign-up` | Passkey registration ceremony; receive 10 single-use recovery codes (shown once) |
| Sign in | `/sign-in` | Passkey authentication; "Use a recovery code" fallback |
| Welcome | `/welcome` | First-time-user onboarding — pick topic chips (Tech / Sports / Nature / Podcasts / Humor) and one-click-subscribe to curated starter feeds. Fires automatically when a signed-in user has zero subscriptions |
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

## Feline contributors

The codebase has occasional unsolicited assistance from the maintainer's cats, who sleep on the keyboard. Their contributions to date include:

```
]88DLSK34///œ¡	≥™ `	‘’:?{))))))))))))))))))))))))))))))))))))))))))))))))))))
```

None have shipped to `main` (yet). Pull requests reviewed but not merged. 🐈
