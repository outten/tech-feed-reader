# Tech Feed Reader

A single-user web application that aggregates public, free RSS / Atom feeds for technology articles, with reading, tagging, search, and summarization tooling. Conventions inherited from [t-money-terminal](https://github.com/outten/t-money-terminal) — Ruby / Sinatra / ERB / RSpec, cache-only render contract, scheduled background refresh — but storage is SQLite (single `data/app.db`, FTS5 for search) instead of `t-money`'s file-per-store JSON.

> **Status: Tier 3 + topic-first reading + observability + chat + digests.** Add feeds via the curated 25-feed catalog on `/feeds` or bulk-import via OPML. Teaser feeds (HN, Lobsters) auto-fall back to a readability fetch. The top-level `/topics` page surfaces the most-talked-about clusters across the last 7/14/30 days so reading is topic-first, not article-first. `/article/:uid` shows an auto-extractive summary, an opt-in Claude LLM summary, and a "Related" panel via FTS5 keyword overlap; rows in `/articles` open in a new tab so `Cmd-W` returns to the list. `/podcasts` groups subscribed shows + recent episodes; a persistent mini-player at the bottom of every page (Hotwire Turbo + `data-turbo-permanent`) keeps audio playing across navigation. `/digests` lists daily snapshots produced by `make digest` (cron-friendly). A floating chat widget on every page lets the user discuss the current page with Claude — context (URL, title, body excerpt) is shipped as the system prompt. Observability stack ships `/health` (liveness JSON), `/metrics` (Prometheus), and `/admin/traces` (OpenTelemetry — in-memory ring buffer + optional OTLP exporter). Mark read / bookmark / archive, filter by state or tag, full-text search via SQLite FTS5. CLI: `make refresh-feed FEED=<id-or-url>`, `make refresh-feeds`, `make scheduler`, `make digest`, `make run-all` / `make stop-all`.

## Getting started

```bash
make install
make seed-feeds # optional: insert the 5 starter feeds (browse 25 more on /feeds)
make run        # dev server with rerun auto-reload → http://localhost:4567
make test       # RSpec — smoke suite passes out of the box
```

Runs on Ruby 3.4.1 (`.ruby-version` pinned). No API keys required to boot — Anthropic API key (for Tier 2 LLM summaries) is the only one wired and is optional.

## Pages

| Page | URL | What it shows |
|---|---|---|
| Dashboard | `/dashboard` | Recent unread, top tags, feed-health banner, activity chart |
| Topics | `/topics` | Trending term clusters with sample articles; 7/14/30-day window selector |
| Topic detail | `/topics/:term` | Synthesized "highlights" + every article in the cluster, summaries inline |
| Articles | `/articles` | Unified reading interface (📄 articles + 🎧 podcast episodes); rows open in new tabs. Filterable by feed / tag / state / kind |
| Article | `/article/:uid` | Single article view + cached summary; podcasts render a "Play episode" button that loads the persistent mini-player |
| Podcasts | `/podcasts` | Subscribed shows grouped freshest-first + recent episodes |
| Digests | `/digests` | Daily snapshots of unread articles + summaries (produced by `make digest`) |
| Digest detail | `/digests/:id` | Inline render of a stored digest |
| Feeds | `/feeds` | Manage RSS subscriptions |
| Tags | `/tags` | User-defined tag rules + activity |
| Search | `/search` | Full-text search across article history |
| Admin | `/admin` | System overview, integration status, sub-page links |
| Cache admin | `/admin/cache` | Per-feed cache age + manual refresh |
| Provider health | `/admin/health` | Per-feed fetch health |
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
