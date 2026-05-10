# Stuff

Random stuff to add to the application.

## [x] CLAUDE_API_KEY

I added my Claude API Key and Name to the .credentials file. Can you integrate and create tests to make sure it works? Implement how it will be used in the application. Also, add a Chat Widget to the application that uses it. Put a chat button on each page at the bottom right that will show a panel for chatting with the context of the page.

Done in commits `bded707` (widget + Chat::Claude module + 22 specs) and `d130a17` (default-closed CSS fix). Verified end-to-end: real PONG round-trip + grounded answer using article excerpt as page context.

## [x] White Listed Shell Actions

I am constantly being asked to approve safe commands like curl, echo, etc. Can you check the VS Code settings for Claude to whitelist all simple shell commands. You did this in a prior commit; however, it is not working.

## [x] Clean Up Branch 001

Let's take a branch to stop and cleanup some items:

- let's be sure to have tooltips for all relevant elements on pages
- on the article page, the Comment and Reload button are stacked horizontally which looks strange, can you do separate buttoms that are verticle with the save this story element
- can you make sure any images for articles and podcasts are used
  - for example, oftentimes a podcast has a Cover Art Picture
- on the UI side, I love inspirational nature pictures, can we use random, free, copyright free pictures as the background on each page ... it should not scroll with the page elements. This may make the look and feel more pleasing.

## [x] Bus Mode

I have a 10-15 minute commute on a SEPTA, Philadelphia, PA bus every day. On most commutes, I listen to a podcast. 

Can you add a Bus Icon in the header before the Refresh All button that will list recent podcasts in order that are less than 15 minutes. Include the usual information for each podcast on the Podcast page. In the same tile format.

## [x] Claude Summarization of a Digest

Add a button on the digest page to have Claude summarize it. Be sure to store the AI summary so we don't have to do it again and waste tokens.

Done on outten/TODO-046. New `Summarizer::Claude.summarize_digest` + cached on the `digests` row via three new columns (`llm_summary`, `llm_model`, `llm_generated_at`, migration `009_digest_llm_summary.sql`). The detail page shows the cached summary above `html_body`; the "Summarize with Claude" button only renders when no cache exists, and the route hard-skips the API call (with a "no new API call was made" notice) if a summary is already stored. 18 examples in `spec/digest_llm_summary_spec.rb`.

## [x] Cosmetics

Shipped in commit `42040f4` (Cosmetics sweep + skim-mode page-preservation bug fix). All seven sub-items merged in one PR; doc catch-up for AGENTS.md followed in `5e637db`.

### [x] 1+2. Sticky-pin on `/article/:uid` (and the title cramp it caused)

> "On the top of page element in the article section, I see that the title of the article is jammed into a column that is too small with width."
> "On the articles page for an article, scrolling pins the first element at the top which is weird and makes it hard to read the other content."

These were the same bug. The global rule `header { position: sticky; top: 0 }` in style.css unintentionally also targeted the inner `<header>` inside `<article class="reading-view"><header>...</header></article>`, pinning the entire article header (hero image + title + subtitle + actions row + tags) to the top while you scrolled the body — which is why both the title looked jammed (squashed into a sticky column) and the rest of the page felt wrong. Fix: scope the sticky to `body > header` only.

### [x] 3. Podcast actions row overflows on `/article/:uid`

> "On the articles page for a podcast, the top element that have a picture of the podcast, pause/play button, mark unread, etc. doesn't fit in the element so things are rendering outside the element."

`.reading-view .actions` was a flat flexbox with no `flex-wrap`. After Phases 3 + 5 added 👍 / 👎 / Mute author / Mute keyword (with an inline text input), the row ran past the right edge on narrow widths. Fix: `flex-wrap: wrap`, gap tightened, and the keyword-mute input narrowed so it doesn't dominate the wrap line.

### [x] 4. Skim-mode thumbnail overlaps the summary line

> "On the articles list page, when you engage skim mode, the picture on the right is over top of the first two lines of text."

`.news-summary-skim` only set a `margin-left` for icon alignment; it didn't reserve space on the right for the absolutely-positioned `.news-item-thumb` (64 px). Fix: hide the thumbnail entirely in skim mode — skim is for fast scan-and-triage, the picture isn't load-bearing here.

### [x] 5. Dashboard "Activity (last 30 days)" is empty

> "On the dashboard page, the 'Activity (last 30 days)' element has no content. Can you add what should be there? Or delete the element."

Real bug. `ArticlesStore.daily_counts(days: 30)` queries 30 days, but `RETENTION_DAYS=7` (the pruner sweeps anything older), so 23 of the 30 days are always zero. The chart shows axes + a flat line. Fix: drive the chart window from `RETENTION_DAYS` and re-label the section ("Activity (last N days)").

### [x] 6. Some podcasts on `/podcasts` are missing cover art

> "Some of the podcasts don't have pictures. I see them in my Apple Podcast app. For example, the 'The Ezra Klein Show'. No biggie if you can get it."

Genuine miss. `FeedParser` already extracts both `<itunes:image>` and `<image><url>`, but some publishers (Vox-published Ezra Klein among them) don't expose either at the channel level. Fix: new `Providers::ITunesLookup` module — queries the public iTunes Search API by show title, returns the first artwork URL — plus a one-shot `make backfill-podcast-images` script that fills `feeds.image_url` for podcast feeds where it's currently null.

### [x] 7. Verbose logging — dev DEBUG, request logs

> "Can you add more verbose logging. For example, I don't see page loads. Development environments should log DEBUG and above. Staging and production should log INFO and higher."

Two-part fix:
- `app/logger.rb` flips its default to `debug` when `RACK_ENV` is unset/development; stays `info` for `RACK_ENV=staging` and `production`; stays `fatal` for `test` (so RSpec output stays clean). `LOG_LEVEL` env var still overrides.
- New Sinatra `before` + `after` hooks emit a single `http_request` JSON line per request with `method`, `path`, `status`, `latency_ms`, `ip`. Logs every request including static assets (per the user's preference for full visibility).

## [x] 8. Triage page 

The layout of the card elements on the page is off. For example, /triage/1 

- The title of the article is vertical instead of horizontal
- can you add a summary of the content for each card

Done on outten/TODO-052. Triage card rows are now full-width vertical cards (reusing the `.sports-article` shape from /sports for visual consistency): h4 title links to the publisher in a new tab, inline article summary via the existing `skim_summary_for` helper (extractive cache → content_text excerpt fallback), italic "Why: …" rationale line, meta row with source / time / author / podcast badge / "Open in app" affordance. Must-read entries keep their green left-edge accent; skip entries stay dimmed. 5 view-surface examples in [spec/triage_card_layout_spec.rb](spec/triage_card_layout_spec.rb).

## [x] 9. Sports Scores

On the sports page, at the top, can you add tiles that show the last game score for the teams we are following. Include date, score, logos of teams, where played, and anything else relevant. Also, add the team's last game on the individual team page.

Done on outten/TODO-052. New `.sports-score-tiles` strip at the top of `/sports`, one tile per followed team that has a synced final from Phase S3+S4. Each tile shows: team logo (or emoji fallback), team short-name, W/L/D pill (color-coded green/red/orange + circle badge), big score line, opponent line ("vs/@ Cowboys" with mini opponent logo), and meta (relative date · venue). Click → that team's `/sports/team/<slug>` page. The same tile renders as a "Last game" section on the per-team page, full-width. ESPN logo capture: `Providers::ESPN.extract_logo` reads `team.logos[0].href`, sync auto-backfills `sports_teams.image_url` for both followed teams + their opponents. Schema fix bundled in: ESPN reuses team IDs across sports (NFL Lions = id 8 = NZ rugby team), so the original `UNIQUE(source_provider, external_id)` was wrong — migration `013_sports_teams_league_unique.sql` rebuilds the table with `UNIQUE(source_provider, league_id, external_id)`. 10 examples in [spec/sports_score_tiles_spec.rb](spec/sports_score_tiles_spec.rb).

## [x] 10. Claude Behavior

Review CLAUDE.md file that contains behavior for Claude. Incorporate this, perhaps the AGENTS.md file might need updating.

CLAUDE.md is now tracked + referenced from AGENTS.md's Documentation files section. The two files are complementary, not overlapping: CLAUDE.md is general LLM-coding behaviour (think before coding, simplicity first, surgical changes, goal-driven execution); AGENTS.md is project-specific architecture (what the codebase looks like, conventions, gotchas). Future agents read both.

## [x] 11. SQLite on S3

> Analysis only — no code change. Question: if we deployed this app to AWS,
> do we need PostgreSQL, or can we keep SQLite by putting the file on S3?

### TL;DR — recommendation

**Keep SQLite. Put the file on a single EBS volume on a single small EC2 instance (or an EFS-backed Fargate task). Use [Litestream](https://litestream.io/) to replicate to S3 for backup + point-in-time recovery. Don't try to run SQLite directly off S3.**

For a single-user reader, that's:
- One `t4g.nano` / `t4g.micro` ($3–8/mo) running the Sinatra app on EBS
- Litestream sidecar streaming WAL frames to S3 every ~1s ($0.05/mo storage + pennies in PUTs)
- Restore = `litestream restore` from S3 on a fresh instance — minutes, not hours

This preserves the things SQLite is great at for our workload (`articles`, `articles_fts` FTS5, transactional writes, sub-millisecond local reads) without paying the operational tax of running PostgreSQL.

### Why not "SQLite directly on S3"

This was the literal question. The two real options people mean:

1. **Mount S3 as a filesystem** (s3fs-fuse, Mountpoint for Amazon S3, goofys). Don't. SQLite uses POSIX-style file locking (`fcntl`) and partial-page writes (a 4 KB page change rewrites just that page, not the whole file). S3 is an object store: every PUT replaces the entire object, there's no atomic compare-and-swap on byte ranges, and S3 didn't even have read-after-write *list* consistency until late 2020. Mountpoint for S3 [explicitly does not support random writes](https://docs.aws.amazon.com/AmazonS3/latest/userguide/mountpoint-usage.html#mountpoint-write-mode) — it's append/upload-only. SQLite under any of these will corrupt within minutes of a real write workload.

2. **VFS shims that fetch pages from S3** ([sqlite-s3-query](https://github.com/uktrade/sqlite-s3-query), the various "SQLite over HTTP" experiments). These work for **read-only** databases. The trick: build the SQLite file once, upload to S3, the VFS does HTTP range requests for the pages it needs and uses ETags as a poor-man's cache key. Great for "ship a static dataset to a Lambda." Useless for an app that ingests 50 RSS feeds every 10 minutes.

The real "SQLite + cloud blob storage" answer is **streaming replication of the WAL**, not running SQLite *off* the blob store. Litestream and [LiteFS](https://fly.io/docs/litefs/) both do this well. You write locally, they ship the WAL frames to S3.

### Why not PostgreSQL

PostgreSQL would also work — RDS `db.t4g.micro` is ~$13/mo + ~$2.50/mo for 20 GB gp3, plus a NAT/VPC story if the app runs outside the RDS subnet. None of that is hard, but it adds:

- A separate process / service to manage (or pay AWS to manage)
- A network hop on every query (vs. SQLite's in-process, ~1µs per query)
- Schema-migration tooling that handles transactional DDL differently from SQLite's `ALTER TABLE … ADD COLUMN`-only constraint
- Loss of FTS5 — Postgres has `tsvector` / `pg_trgm` which are fine but require rewriting [app/articles_store.rb](app/articles_store.rb) `search` and `for_topic`

For a multi-user, write-heavy app with replicas, all of that cost is justified. For *this* app — single user, single writer, ~100k row scale, FTS5-heavy — it's pure overhead.

### What we'd actually need to handle

The only real risk with SQLite-on-EBS-with-Litestream is the **single-writer** constraint. Today our writers are:

- Web request handlers (one user, low concurrency)
- `make sync-feeds` cron (every 10min)
- `make digest`, `make triage`, `make sync-sports` crons (daily-ish)
- The dev-server background reload

WAL mode (already set in [app/database.rb:96](app/database.rb#L96)) lets readers run concurrently with one writer, and short writers serialize cleanly. A single-instance deploy keeps all writers in one process tree, which is the only configuration where SQLite is safe. Don't run it behind an autoscaling group with `min_size > 1`.

The Litestream story handles **disaster recovery**: if the EC2 instance dies, you spin a new one, `litestream restore`, and the app is back with at most ~1s of write loss (the replication lag). For backups, Litestream ships continuous snapshots — easier than PostgreSQL's `pg_basebackup` ceremony for this scale.

### Concrete deploy sketch (if we ever ship)

```
EC2 t4g.nano (or Fargate w/ EFS mount)
├─ /var/app/tech-feed-reader/  ← code
├─ /var/lib/db/feed-reader.db  ← EBS-backed SQLite + WAL
├─ litestream replicate ──→ s3://tfr-litestream-<uniqueid>/
└─ cron: sync-feeds, digest, triage, sync-sports

Cost: ~$5–8/mo for a single-user instance + $0.10/mo for S3 replication.
```

If usage ever grows to multi-writer or multi-region, **that's** when PostgreSQL (or LiteFS for SQLite-with-failover) earns its keep. We're nowhere near that point.

### What I considered and rejected

- **Aurora Serverless** — overkill, expensive at idle, network hop per query.
- **DynamoDB** — kills the relational model; FTS5 has no equivalent.
- **EFS + SQLite without Litestream** — EFS is NFSv4. SQLite's locking on NFS is officially [discouraged](https://www.sqlite.org/faq.html#q5) and historically buggy. Possible, but Litestream-on-EBS is simpler and cheaper.
- **DIY rsync to S3** — Litestream solves this exact problem, no point reinventing.

## [x] 12: Attribution of Background Image

The podcast element on pages is great. However, I think it is rendering over the information and attribution of the background page image that I like a lot. I want to make sure the artists get attribution as they are very much a part of the UI/UX of the application. Can you make sure the artists are take care of. And can you up the count or random images to say 50 -- they are so inspirational.

**Fix.** The fixed `#global-player` (`position:fixed; bottom:0`) was overlapping the `<footer>` that holds the `data-bg-attribution` slot, hiding the artist credit whenever a podcast was loaded. The existing `body.has-mini-player main { padding-bottom: 5rem }` only padded `<main>` — but the footer lives OUTSIDE main, so it slid under the player. Moved that rule to `body.has-mini-player { padding-bottom: 5rem }` so the entire body (main + footer) clears the player bar. Also bumped `BackgroundPool::POOL_TARGET_SIZE` from 12 to 50, giving the next "Refresh pool" click a much larger rotation set.
