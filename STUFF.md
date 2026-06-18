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

## [x] 13: Home Page

This application is very useful. Thank you. Let's prepare to open this to other users.

Before we restructure the database, etc. I'd like to focus on the home page.

The hone page should be very friendly to new users. It should express the vision of this project: to aggregate information on topics that the user cares about; the change user behavior from swivel chairing between site -- i.e. we bring relevant and personalized inform to YOU verus you hunting for information; we prioritize information, based on your behavior and preferences, for you; we summarize information based on AI; we allow you to efficiently skim data; and your podcast listening plays consistently across pages while you are reading articles.

In addition to the home page, this should be expressed fully in an About page for the application.

**Shipped.** New `/` shows a marketing home for first-time visitors (hero + 6 feature cards mapping to the vision pillars + a "why" narrative + a final CTA), and a `tfr_seen` cookie redirects subsequent visits to `/dashboard` so the existing single-user owner keeps their muscle memory. Six screenshots captured via Chrome headless ([public/img/home/](public/img/home/)). New `/about` page covers the philosophy, anti-swivel-chair argument, how-it-works, what's-different, tech stack, and get-started. Footer "About" link renders on every page. Multi-user / auth / DB restructure stays bracketed for later — the cookie's `tfr_seen=1` guard becomes the natural place to plug "is logged in" when that arrives.

## [x] 14: The Tech Link

In the header, the TITLE card link should link to the link / with a refresh.

/ should he usuablize to the user's preferences. Generalize in the first time, then personalized.

**Shipped.** The header "Tech Feed Reader" title is now a link to `/` with `data-turbo="false"` so the click does a full document refresh (rather than a Turbo SPA swap). The `/` route stays at the same URL but branches its hero based on `ReadStateStore.any_activity?` — first-time visitors see the original "Stop swivel-chairing" pitch; returning users (anyone with a row in `read_state`) see a "Welcome back" hero with their unread / bookmarked / article counts, last-triage timestamp, top-3 unread picks, and CTAs into `/articles?sort=relevance` + `/dashboard`. The six feature cards stay below either hero so the vision pillars are always visible. No cookie used — the DB probe is the source of truth, and once auth ships in Phase A1 it becomes "is signed-in user."

## [x] 15; The Links Header

Can you links how to links in the header can be better for UI/UX. There are too many.

**Shipped.** Nav consolidated from 11 flat links to **6 visible + 2 dropdowns + a search icon**: `Dashboard | What's On | Articles | Podcasts | Sports | AI ▾ | Manage ▾ | 🔍 | Admin`. **AI ▾** holds Topics / Triage / Digests; **Manage ▾** holds Feeds / Tags. Dropdowns are pure CSS via `:hover` and `:focus-within` (no JS needed; keyboard-accessible). Active highlighting propagates: visiting `/triage` lights up the AI parent; visiting `/feeds` lights up the Manage parent.

## [x] 16. YouTube

I love YouTube and have a subscription. And about how to use subdcribitions? I love natture hows by BBC Activity (last 7 days). Dadiv Abbenborough.

**Shipped.** YouTube exposes a standard Atom feed per channel at `https://www.youtube.com/feeds/videos.xml?channel_id=UC...`, which our existing `FeedParser` handles with no special-casing. New `:nature` topic and `:youtube_nature` category in `FeedCatalog`, seeded with six verified channels: **BBC Earth**, **BBC Earth Science**, **National Geographic**, **Nature on PBS**, **Natural World Facts**, and **Free Documentary - Nature**. Channel IDs verified live via `curl` against each `.../videos.xml` URL on 2026-05-10. You can browse all six on `/feeds` under the new "Nature & Documentary" topic and add more channel URLs the same way. Once subscribed, videos flow into `/articles` like any other feed and surface in the new "To watch today" section on `/whats-on` (item #17).

## [x] 17. What's on the World Today

As we are expanding to at world wide audience of Sports Fans. Can we add a top level section, "whats on" that listens sports, legends, etc. that are personalized to the user.

**Shipped (v1, sans "legends").** New top-level `/whats-on` page pulls from data we already track and filters to *today*, personalized by the user's follows + the For You ranker. Four sections, each only rendered when it has rows: 🏟 Sports today (fixtures for followed teams in the next 24h), 📰 To read today (articles ranked by For You), 🎧 To listen today (podcast episodes published today), 📺 To watch today (articles from `topic = 'nature'` feeds — i.e. the YouTube channels from item #16). Empty-state copy when nothing's happening. Top-level nav link added between **Dashboard** and **Articles** in the consolidated header (item #15). "Sports legends" deferred — once we have a clear data source (anniversaries via Wikipedia? a hand-built list?) we'll layer it in.

**Update.** What's On Today is now the home page itself: GET `/` shows the marketing pitch for anonymous visitors (no `read_state` activity), and the four What's On sections for returning users. The dedicated `/whats-on` URL is a 301 redirect to `/`. The Dashboard (operational stats + Activity chart) moved to `/admin/dashboard` since it's an ops view, not a daily-use surface; `/dashboard` 301-redirects there. Both `Dashboard` and `What's On` links removed from the main nav (the title click lands you on the home, and `/admin/dashboard` is linked from the admin index).

## [x] 18. Development areas

Can we add areas / topics for:

- Cyber: Cyber security
- development: software development
- mythos: Claudus Mythos model

**Shipped.** Three new categories under `:technology`: `:cyber` (renamed from `:security`, now broader — kept the existing Krebs / Schneier / Bleeping Computer and added **Dark Reading**, **The Hacker News**, **CSO Online**), `:development` (Martin Fowler, Joel on Software, A List Apart, CSS-Tricks, Coding Horror), and `:mythos` (classical / Greek / Norse mythology — Aeon, Daily Stoic, Myths and Legends podcast, Stuff You Missed in History Class). All 12 new feed URLs verified live via curl on 2026-05-11. Catalog total: 60 → 72.

### [x] Links on the Articles Page (#19)

For some pages, they are relative. Check and make relaive to the realiative spot.

**Shipped.** `/articles` was the lone outlier: its article-title links carried `target="_blank"` while every other listing surface (`/whats-on`, `/sports/*`, `/digests`, `/triage`) opens internal `/article/:uid` links in the same tab. Fixed `/articles` AND the **Read-next** card on `/article/:uid` (which had the same bug). External publisher URLs (`@article['url']`, `@espn_url`, etc.) still carry `target="_blank"` + `rel="noopener noreferrer"`. New regression spec [spec/internal_link_target_spec.rb](spec/internal_link_target_spec.rb) locks the convention so a refactor can't quietly reintroduce the inconsistency.

## [x] 19. Can't play

On the play article play can't play if played before.

**Shipped.** Root cause: after an audio element fires `ended`, its `currentTime` is parked at `duration`. The "Play episode" button (and the mini-player ▶ button, and `window.Player.toggle/resume`) all called `audio.play()` with no rewind — so on a finished episode `play()` had nothing to play and fired `ended` again immediately. The button looked broken. Added a `rewindIfAtEnd()` helper in [public/global-player.js](public/global-player.js) that resets `currentTime = 0` whenever the audio is at-end (`audio.ended` OR within 0.5s of duration), and wired it into every code path that initiates playback: the article-page Play button → `loadEpisode` (same-uid branch), the mini-player ▶ click, `window.Player.toggle`, and `window.Player.resume`. Pause paths unchanged. Suite: 948/0 (JS-only — no Ruby regressions).

## [x] 20. Documentation Skill

Can you write a skill to always update our documentation with new features, bug fixes, etc. When we merge, our docs should always be up to date.

**Shipped.** New project-local skill at [.claude/skills/update-docs/SKILL.md](.claude/skills/update-docs/SKILL.md) — invoke with `/update-docs`. Scans `git log` for recent merges, classifies each as feature / bugfix / refactor / docs / infra, and emits precise `Edit` calls against README.md, AGENTS.md, TODO.md, STUFF.md (and SPEC.md when a non-goal changes). Read-only on code; doc-only edits. The AGENTS.md "Documentation rule" block now points at the skill as the catch-up tool when drift sneaks in between sessions. The standing rule remains: every PR keeps its own docs honest as it lands — `/update-docs` is for sweeping up missed updates, not as a substitute.

## [x] 21. Unsplash

Can you double the number of unsplash random background inpirational, pictures. I like them a lot, partciularly nature and technology.

**Shipped.** `BackgroundPool::POOL_TARGET_SIZE` bumped 50 → 100. That's the page-size ceiling Picsum's `/v2/list` endpoint returns in a single hit, so we're maxing out the per-fetch variety. Click "Refresh pool" on `/admin/backgrounds` to populate. Note: Picsum is unfiltered random — Unsplash's themed endpoints (nature / technology specifically) would require an API key + a different provider integration; happy to do that as a follow-up if 100 random images isn't enough variety on the themes you like.

## [x] 22. Consumer Facing and Multi-Users

I've decided to change this from a Enterprise / Company app and make this for consumers.

So, update the TODO / Microsoft Entra area to reflect this. Also, recommend which type of login we should use:

- email / password
- text message
- passkey

**Analyzed + locked.** Phase A1 in [TODO.md](TODO.md#multi-user--phase-a1-auth-wall-passkey-only-consumer-facing) rewritten end-to-end. Decision: **passkey-only with one-time recovery codes**. No email anywhere (explicit user direction); no SMS (per-message cost + privacy + SIM swap); no password (adds breach surface for zero gain when the recovery story is non-email). User identity is a chosen username; 10 recovery codes generated at signup hashed with HMAC-SHA256 + `SESSION_SECRET`, shown once. Library: `webauthn` Ruby gem (Mastodon + GitLab use it). No external services, no per-login cost. Three new tables (`users`, `webauthn_credentials`, `recovery_codes`). Phase A2 (per-user data split) is unchanged — provider-agnostic.

## [x] 23. Use AI to suggest feeds to add

On the feeds page, add a input box to ask the AI to do and analysis and add feeds for the set to consider subscribing too. For example, "Can you make recommendations on feeds, podcasts, and YouTube follwers that focus on Food & Travel? I really like Anthony Bordain and his travels in Asia, perhaps there are recommendations you can make." 

As the application is about to be multu-user, the number of Feeds that we know about (ie. database) will grow significantly. On the Feeds page, we need:

- a good search option to find feeds by keyworks, tages, etc.
- we don't want a long list of possible feeds that a user can subscribe to, we should use personalization, etc. to help direct the user to feeds they will enjoy

All feeds should be free.

**Shipped.** `/feeds` now has an "✨ Ask AI for feed ideas" section above the existing Recommended-for-you callout (visible when `ANTHROPIC_API_KEY` is set). Type a free-text prompt, the route calls `FeedRecommender::Claude.recommend` with your prompt + a JSON list of your current subscriptions + every catalog entry you're NOT subscribed to, and Claude picks up to 8 with a one-line rationale. URLs are validated against the catalog before render (no hallucinations); subscribing is one click via the existing `/feeds/catalog/add` flow. Catalog browse is the safety boundary: every recommendation is from a pre-vetted free feed. Search / categories / catalog-wide discovery beyond what the 79-entry catalog provides is **#27**'s scope.

## [x] 24: Most Popular

As we are now multi user, can we add a Top Chars for each type of Feeds our user are accessing: News, Sports, Podcasts, Nature, YouTube, etc. The doal is Discovery and making it easy to users to "sumble" into new content. That is a key focus of this application.

**Shipped.** New "🔥 Popular with other readers" section on `/feeds`, between the "Recommended for you" callout and the full catalog browse. Five mutually-exclusive type buckets — 📰 News, 🏟 Sports, 🎧 Podcasts, 📺 Nature, 🎬 YouTube — each rendered as a top-5 strip ranked by distinct subscriber count desc (tiebreak: feed id asc). Bucket assignment: `youtube` matches the canonical `youtube.com/feeds/videos.xml` URL pattern; `podcasts` is any feed with at least one article carrying `audio_url`; the remaining three are `topic = 'sports' / 'nature' / IN ('technology','general')` with podcasts + YouTube excluded so a feed never appears in two charts. Single-user world: every feed shows `1 subscriber` today; the chart goes live automatically once multi-user data starts accumulating. Subscribed feeds carry the existing `✓ Subscribed` badge; unsubscribed feeds show an `+ Add` button (routes via `/feeds/catalog/add` for curated feeds, `/api/feeds` for arbitrary URLs). New `FeedsStore.popular_by_type` + `views/_popular_feeds.erb`; 8 store specs + 5 view-route specs in [spec/feeds_store_spec.rb](spec/feeds_store_spec.rb) and [spec/feeds_popular_route_spec.rb](spec/feeds_popular_route_spec.rb).

## [x] 26. YouTube

Can you add YouTube as a top level item in the header? The page it loads should like our YouTube subscribe channels. There should be a link to take you directly to a channel in a new tab. Also, can you do an analysis to see if it is possible to:

- have a subpage with a list of the 10 most recent videos
- clicking a video uses takes you to the page with the embedded player

**Shipped.** New top-level `YouTube` nav link between Podcasts and Sports. `/youtube` lists subscribed YouTube channels as a card grid (cover art + video count + latest age) with a small `↗ Channel` deep-link that opens the channel on YouTube in a new tab. `/youtube/:feed_id` shows the 10 most recent videos as 16:9 tiles using YouTube's `hqdefault` thumbnail + a center play overlay; clicking a tile lands on `/article/:uid`, which already embeds the YouTube player (shipped earlier in STUFF #19). New `ArticlesStore.youtube_channels(user_id)` paralleling `podcast_feeds`, matched on the canonical `youtube.com/feeds/videos.xml?channel_id=UC…` URL pattern.

## [x] 27. Feed Filtering

The list of items on the feed list are getting very long. Can you make a suggestion on how to filter the list so that the user can easily find and discover a feed? Consider:

- search
- AI
- personalization
- categories
- subscribed
- unsubscribed
- etc.

Do an anlaysis. Thank you.

**Shipped (Phase 27.1).** Each long list on `/feeds` now has a filter toolbar at the top: a `<input type="search">` that narrows by title / URL / blurb substring, plus topic chips (`All / Tech / Sports / Nature / General` for subscribed; `All / Tech / Sports / Nature` for catalog). Search + chip combine as AND. Pure client-side filter (`public/feeds-filter.js`) — no server round-trip. Catalog category headings auto-hide when every row beneath is filtered out; a small "showing N of M" counter appears when the result is narrower than the full list. Rows carry `data-topic` / `data-search` from the existing `feed.topic` column and `FeedCatalog::CATEGORY_TO_TOPIC`. Deferred to follow-up phases: a "hide already-subscribed" toggle on the catalog (27.2), sort options on the subscribed table (27.3), and cross-user "most popular" ranking (that's STUFF #24, separate).

## [x] 28. Topics

On the /topics page, the topics are off. I see things like: com, https, can, said, comments, instagram. Can you analyze? Perhaps we need to:

- use a "topic" field is it is in the feed description
- use relevant keywords in the description
  - prabably need to do weighted keywords
- eliminate anything vague

And we should run this on all existing and future contents.

**Shipped in four phases on one PR.** Topic-cluster quality overhaul addressing every part of the complaint plus a follow-up on multi-word names.

**Phase 28.1 — stopword + URL hygiene.** Root cause of the user-reported tokens: bare URLs in `content_text` were tokenized into `com` / `https` / `www`, and the `STOPWORDS` list in [extractive.rb](app/summarizer/extractive.rb) was missing common modals (`can`, `said`, `told`), site/social boilerplate (`comments`, `subscribe`, `instagram`, `twitter`, `facebook`), time-vague words (`today`, `year`), and filler verbs (`get`, `make`, `look`). [recommendation.rb](app/recommendation.rb) now strips URLs, emails, and bare hostnames *before* tokenization; `STOPWORDS` expanded ~5x with named buckets. No schema change — `/topics` renders correctly on the next page load. 7 regression specs in [spec/recommendation_spec.rb](spec/recommendation_spec.rb) lock the user-reported tokens.

**Phase 28.2 — publisher-supplied categories.** New `articles.categories` column (migration `023_articles_categories.sql`; JSON-encoded array of normalized strings). [FeedParser](app/feed_parser.rb) extracts `entry.categories` (feedjira normalizes RSS `<category>` and Atom `<category term="…">` into the same accessor), downcases + trims + dedupes + splits comma/semi-packed values + caps at 10 per entry. [ArticlesStore.import](app/articles_store.rb) writes the column on new inserts; on duplicate uid it runs a separate UPDATE that fills `categories` *only if it's still NULL*, so the existing corpus backfills naturally over the next 24h of sync-feeds cycles (manual immediate backfill: `make refresh-all`). 6 parser specs + 2 store-backfill specs.

**Phase 28.3 — weighted scoring + ubiquity ceiling.** [TopicClusters.recent](app/topic_clusters.rb) was rewritten end-to-end: each article contributes its categories at weight 2.0 and its top-5 body keywords at weight 1.0; for each candidate term we sum contributing weights (deduped per-article — a term hit by both signals on the same article uses the higher weight, not the sum), then drop any term in > 50% of the corpus (only applied when the corpus has ≥ 20 articles, so unit tests don't trigger it accidentally), then drop a small `CATEGORY_STOPWORDS` list (`news`, `article`, `general`, `featured`, etc. — the brand-noise tags many feeds emit on every entry). 6 new TopicClusters specs (noise-token regression, category-only surfacing, weighted ordering, brand-noise filtering, ubiquity ceiling on a 25-article corpus).

**Phase 28.4 — proper-noun phrase detection (e.g. "Jannik Sinner").** User reported that names like `Jannik Sinner` were splitting into two unigram clusters (`jannik` and `sinner`) that never combined. New `Recommendation.top_phrases` extracts adjacent-capitalized bigrams (`[A-Z][a-z]+ [A-Z][a-z]+`) from the original-case text *before* tokenization, downcases them, and filters via a narrow `PHRASE_STOPWORDS` set (articles + pronouns + interrogatives — so "The President" / "What Trump" get filtered as sentence-initial false-positives, but "New York" / "North Dakota" survive because `new`/`north` aren't in the phrase-stopword list even though they ARE in the broader single-word `STOPWORDS`). `TopicClusters.weighted_terms_for` emits phrases at `PHRASE_WEIGHT = 1.5` (between body keywords 1.0 and publisher categories 2.0) and suppresses the unigram components of any phrase emitted for the same article, so `jannik sinner` wins cleanly instead of competing with sibling `jannik`/`sinner` clusters. Bigram-only (not trigram) by design — `String#scan` non-overlapping advance breaks down on tightly-packed mentions otherwise, so `"New York City"` collapses to `"new york"` as a deliberate trade. URL routing + FTS5 already handle multi-word terms (`CGI.escape` in the existing views; FTS5 `MATCH "jannik sinner"` AND-joins the tokens). 7 new `top_phrases` specs + 1 TopicClusters integration spec for the Sinner scenario.

**Phase 28.5 — single home for the stopword lists.** Follow-up to #28.1 below: the three lists (~250 + 24 + 14 words) were scattered across `extractive.rb`, `recommendation.rb`, and `topic_clusters.rb`. Consolidated into a single `app/stopwords.rb` module exposing `Stopwords::GENERAL` / `Stopwords::PHRASE` / `Stopwords::CATEGORY`. All three consumers reference back to it; no behavior change, all 1129 specs still green.

**Suite: 1129 examples, 0 failures** (was 1101; 28 new specs + a zero-cost refactor).

## [x] 28.1: Keywords

Are you storing the keywords in the database, a text file, code, etc.? They probably won't change in a very long time. Where should they be stored and managed?

**Answer + shipped (Phase 28.5).** Before #28.1 was raised, the three stopword lists lived in three different Ruby files (one beside each consumer). Consolidated into a single module at [app/stopwords.rb](app/stopwords.rb) exposing `Stopwords::GENERAL` (~250 words — single-word topic + summary filter), `Stopwords::PHRASE` (24 words — phrase-rejection articles/pronouns), and `Stopwords::CATEGORY` (14 words — publisher-tag brand noise). One greppable home; relationships between lists are now visible (e.g. `PHRASE ⊂ GENERAL` mostly, but intentionally narrower so `new`/`north`/`first` aren't in PHRASE — they ARE legitimate first words of proper-noun phrases). Lists stay in Ruby (not YAML/DB) because (a) they change rarely so a code review is the right gate, (b) zero parse overhead at boot, and (c) a too-broad word here can nuke a legitimate cluster, which is exactly the kind of change that benefits from PR review.

## [x] 29: A1 and A2

What is left in A1 to do before moving to A2?

**Reality check + shipped.** Both A1 and A2 already landed before this question was raised:

- **Phase A1** (auth wall, passkeys, recovery codes) — `a9e5032` (#88)
- **Phase A2.0** (per-user data split — migration 022 + stores + routes) — `7b1533a` (#89)
- **Phase A2.1 + A2.2** (explicit `user_id` everywhere + cross-user isolation specs) — `7b7bcca` (#90)

What WAS left was the top three A1 deferrals — multi-passkey UI, account deletion, and self-serve revoke. All three landed in the account-management PR this question prompted.

**Shipped — `/account` page** with four sections behind the auth wall:

1. **Profile** — edit display name (free-form, 80-char cap, empty falls back to username; `UsersStore.update_display_name!`).
2. **Passkeys** — table of registered credentials with `created_at` + `last_used_at`; a `+ Add this device as a passkey` button kicks off a fresh WebAuthn ceremony (`POST /account/passkey/options` → `verify`) scoped to the signed-in user via session (no username needed); per-row Revoke button with lockout protection (refuses to delete the last passkey when zero unused recovery codes remain — caller gets a friendly error explaining why).
3. **Recovery codes** — shows unused count; Regenerate button wipes the old batch + mints a fresh 10, shown ONCE on the next page render (session-passed plaintext list, cleared after first render).
4. **Delete account** — `<details>` reveal → typed-username confirmation form. `POST /account/delete` only succeeds when `confirm_username` matches the signed-in user's username (case-insensitive). Cascade-deletes through the FK chain on migration 022 (per-user tables) + `webauthn_credentials` + `recovery_codes`. Shared catalog rows (`feeds`, `articles`) stay. Signs out + redirects to `/` with a notice.

**Header chip is now a link** to `/account` (was a plain `<span>`); CSS adds a hover state.

**Lockout protection logic**: refuses to revoke the user's last passkey when `RecoveryCodesStore.unconsumed_count_for(user) == 0`. Documented in the error message: "Add another passkey or regenerate recovery codes first." Means a careful user can never lock themselves out via the UI.

**Specs**: 18 new examples in [spec/account_routes_spec.rb](spec/account_routes_spec.rb) — wall enforcement, display-name update (including blank-fallback + length cap), passkey revoke with + without lockout protection, recovery-code regenerate + once-only render, account-delete (with all four typed-confirmation paths: missing / mismatched / case-insensitive match / cascade verification), add-another-passkey ceremony, header chip as link. **Suite: 1169/0** (was 1151; 18 new examples).

**TODO.md updated**: A1 + A2 sections flipped to ✅ with pointers to the shipping PRs; new "Multi-user — open follow-ups" section enumerates the remaining nice-to-haves (admin user list, account-export endpoint, `WEBAUTHN_RP_ID` production target).

## [x] 30: Add to YouTube List

Can you add the ability on the /youtube page to give a list of channels to add to a user's YouTube channel list? Example: `@PBSNewsHour`. Allow the user to specify multiple channels in one request.

**Shipped.** New `+ Add channels` section on `/youtube` with a textarea — paste up to 25 lines, one channel per line, hit the button. Submit goes to `POST /youtube/subscribe-bulk`, which resolves each line via the new [`Providers::YouTubeChannelResolver`](app/providers/youtube_channel_resolver.rb) and routes each successful resolution through the existing `FeedsStore.add_for_user` flow. Per-line results render inline (✓ subscribed / ✓ subscribed-pending-fetch / ℹ already subscribed / ✗ not found / ⚠ error) with status-color borders.

**Background fetch on new feeds.** Brand-new feeds (never fetched before — `feeds.last_fetched_at IS NULL`) get a `FeedRefreshWorker.perform_async(feed_id)` enqueued so the channel grid populates within ~30s instead of waiting for the next scheduler tick. The result row shows an italicized hint: *"Give the system ~30s to fetch the channel's recent videos, then refresh this page."* Feeds another user already subscribed to (so content is already imported) skip the refresh — they go straight to the plain ✓ Subscribed message.

**Resolver accepts every shape a user might paste:**

- `@PBSNewsHour` / `PBSNewsHour` — bare @handle or handle alone
- `https://www.youtube.com/@PBSNewsHour` — handle URL
- `https://www.youtube.com/c/PBSNewsHour` / `/user/…` — legacy custom URLs
- `https://www.youtube.com/channel/UC…` — direct channel URL
- `https://www.youtube.com/feeds/videos.xml?channel_id=UC…` — already-canonical feed URL
- `UC…` — bare channel id

**How it resolves:** direct-UC paths go straight to the feed XML (one HTTP, validates + grabs title); handle/legacy paths scrape the channel page HTML for the embedded `"channelId":"UC…"` token (stable for years, used by every third-party YouTube-to-RSS tool) with a fallback to `<link rel="canonical">`. Title comes from `og:title` (or the Atom feed `<title>`); HTML entities decoded. No API key required.

**Why synchronous + 25-line cap**: at ~1–2s per resolve, 25 channels is ~30–50s worst case — fine for an occasional bulk-add. If larger batches become common we have Sidekiq for the async path.

**Specs**: 15 resolver examples (every input shape, network-failure, HTML-without-channelId, entity decoding) in [spec/providers/youtube_channel_resolver_spec.rb](spec/providers/youtube_channel_resolver_spec.rb); 5 route examples (subscribe-with-pending-fetch / subscribe-skipping-fetch-when-content-exists / cap-truncation / empty-input / error-path) appended to [spec/youtube_routes_spec.rb](spec/youtube_routes_spec.rb). **Suite: 1151/0** (was 1129; 22 new examples).

## [x] 31. Digital Ocean

Let's prepare to deploy application to Digital Ocean.

- terraform as infrastructure as code
- Digital Ocean Managed PostgreSQL
- Digital Ocean service for running a containerized application

**Shipped 2026-05-17.** The full Digital Ocean stack is live at https://feeder.tmoneystuff.com:

- **Terraform** (`terraform/`): Droplet (s-1vcpu-2gb, ~$12/mo), cloud firewall, DO Space for backups (~$5/mo), DNS A record on DO-managed domain, and Phase 5's Managed PostgreSQL cluster (db-s-1vcpu-1gb, ~$15/mo) with database-firewall trust-list. Total ~$32/mo. PRs #102 (scaffold) → #109 (DO DNS rewrite from Cloudflare) → #110 (variable-description escapes) → #115 (PG cluster).
- **Containerized app**: multi-stage Dockerfile + docker-compose (app + sidekiq + redis + caddy reverse-proxy). PRs #104 (compose + Caddy) → #117 (DATABASE_URL plumbing).
- **PostgreSQL cutover**: SQLite → managed PG via the dump script + thread-safe adapter hotfix. PRs #111–#118 (Phase 5: D-PG-1 through D-PG-5).
- **TLS**: Caddy auto-mints Let's Encrypt cert on first HTTPS hit. HSTS at 6h (bump to 1y after a week of stability).
- **CLI**: just `terraform` + `gh` + `ssh`. No `doctl` needed yet — that joins the stack in #33 (DOCR + image publish pipeline).

## [x] 32. Update Homepage and About for logged out user


As the application is no longer single user, can you update the copy of the welcome / home page?

**Shipped on PR #120.** `/` (anonymous branch) and `/about` rewritten for the hosted multi-user / managed-PG era: drops "self-hosted, single-user," reframes data-on-disk → per-account row scoping, retargets anonymous CTAs at `/sign-up` (they were silently 302-ing to `/sign-in` from `/articles`), and refreshes the About "How it works" + "Tech stack" sections (SQLite → PostgreSQL with tsvector + GIN, cron → Sidekiq, WebAuthn added). Two specs in `spec/home_about_spec.rb` updated to lock the new CTA hrefs.

## [x] 33. VERSION AND DOCKER IMAGE

When deploying, I'd like to have three directives in the makefile:

- deploy-major: update the major version in VERSION
- deploy-minor: update the minor version in VERSION
- deploy-patch: update the patch version in VERSION

Write a script to do this.

All the deploys should do tests. IF the tests pass, then deploy to Digital Ocean.

The VERSION can be used to tage the Docker image.

I reinstalled Colima locally. This will allow us to make docker images locally for development and testing. Should we change our deployment process to:

- build the container locally
- run tests ... if tests pass
- push it to Digital Ocean's docker image registry
- trigger a redeploy of the application

Also, I've added the CLAUDE credentials to the .env file?

BTW. We should have VERSION in the footer and health endpoint so we know what we are looking at.

---

**Shipped 2026-05-18 as v0.9.0 — the first registry-versioned release.** Five PRs, sliced into 33A (versioning + visibility) and 33B (DOCR + image-publish pipeline) with three small follow-ups.

- **PR #119** — `make deploy` on the Droplet (one-liner: `git pull` + `docker compose pull/up`).
- **PR #122 — 33A**: `scripts/bump_version.rb major|minor|patch` (10 specs), Makefile `release-major/-minor/-patch` targets (test-gated + tag + push), `AppVersion::SEMVER` constant reading `/VERSION`, footer renders `v0.9.0` next to "shuffle background", `/health` JSON now exposes both `version` (semver) and `git_sha`, Dockerfile `ARG APP_VERSION` + OCI `org.opencontainers.image.*` labels.
- **PR #123 — 33B**: `terraform/registry.tf` provisions `digitalocean_container_registry.main` (Basic tier, ~$5/mo, name `tfr`). `make publish-image` uses `docker buildx build --platform linux/amd64` to cross-compile from arm64 Mac → amd64 Droplet, tags both `:<version>` + `:latest`, pushes to DOCR. Compose `image:` for `app` + `sidekiq` resolves to `${IMAGE_REGISTRY}/tech-feed-reader:${IMAGE_TAG:-latest}`; pin `IMAGE_TAG=0.9.3` in `/opt/app/.env` for tag-pinned rollback.
- **PR #124** — restored `make deploy` (squash-merge of #119 dropped its Makefile change during the main-merge conflict resolution) AND wired the runtime-stage `ARG APP_VERSION=unknown` re-declare so BuildKit stops warning about UndefinedVar.
- **PR #125** — defensive AppVersion fix after the first publish exposed Ruby's `||`-treats-empty-string-as-truthy trap (the pre-#124 image had `APP_VERSION=""` baked in, so the footer rendered `v` with no number). `AppVersion.resolve_semver` now explicitly empty-checks ENV before the file fallback. Same PR added `sudo apt install -y make` to the DEPLOYMENT.md Phase 6 Droplet bootstrap.

Per-release workflow (steady state, ~3 minutes total):
```
# Laptop:
make release-patch        # tests pass → bump VERSION → tag → push
make publish-image        # buildx amd64 → push :X.Y.Z + :latest to DOCR

# Droplet:
ssh deploy@<ip> 'cd /opt/app && make deploy'
```

The DOCR pipeline costs $5/mo. Deferred to a later phase (only worth it if/when CI/CD auto-publish becomes valuable): build-on-merge via GitHub Actions.

## [x] 35. PostgreSQL

- when do we plan to update the database to Digital Ocean Managed PostgreSQL

**Shipped 2026-05-17 as Phase 5 (5 PRs + manual cutover).**

- **D-PG-1** (#112): `pg` gem + `Database::PgAdapter` (thin wrapper around `PG::Connection` exposing the same surface as `SQLite3::Database`). SQLite stays the default; PG opt-in via `DATABASE_URL`.
- **D-PG-2** (#113): consolidated PG-dialect baseline migration in `db/migrations-postgres/001_init.sql` — BIGSERIAL ids, tsvector + GIN replacing FTS5, ANSI `ON CONFLICT` everywhere. `Database.migrate!` is adapter-aware.
- **D-PG-3** (#114): store SQL audit + CI matrix. `INSERT OR IGNORE` → `ON CONFLICT DO NOTHING`, `datetime('now')` → `now()`, dialect branches in `ArticlesStore.search` / `for_topic`, `Recommendation.for_article`, `SportsEntityArticlesStore.fts_search`. CI runs both legs.
- **D-PG-4** (#115): Terraform `digitalocean_database_cluster` + `database_db` + `database_firewall`. Plan-only; no apply.
- **D-PG-4.5** (#116): `scripts/dump_sqlite_to_postgres.rb` round-trip migration tool + spec.
- **D-PG-5** (manual cutover): `terraform apply` created the cluster; dump script copied prod data; `/opt/app/.env` got `DATABASE_URL=…`; redeploy on the Droplet flipped the app to PG.
- **D-PG-5 hotfix** (#118): adapter wrapped in a `Monitor` + reconnect-on-disconnect. Caught immediately post-cutover when Puma's threads desynced libpq.

## [x] 36. PostgreSQL for Development Environment

PostgreSQL is running locally on my system. Do you want to switch to it for development environment so that we can run tests locally?

**Shipped 2026-05-17.** Local cutover during D-PG-5 prep: `createdb tfr_dev` → `DATABASE_URL=postgres://localhost/tfr_dev ruby scripts/migrate.rb` → dump script copied the full SQLite dev corpus (2 users / 82 feeds / 19,398 articles / 18,693 summaries) into PG. `.env` already pointed at `tfr_dev`, so `make run` boots against PG with no further change. The test suite gates on `TEST_DATABASE_URL` (defaults to `postgres:///tfr_test`) so CI's matrix runs both legs; `bundle exec rspec` against the laptop SQLite path remains the unchanged default for anyone who doesn't have PG installed.

## [x] 38. Drop SQLite3

Now that we are on PostgreSQL, let's drop SQLite3 testing.

(Renumbered from a duplicate `#36` — original `#36` was the PostgreSQL dev-environment item just above this one.)

**Shipped as part of STUFF #47 — same work item, two entries.** See #47 below for the full changelog.

## [x] 37. Beauty Pass

Can you review the App for beauty? It is awesome, but the UX can be better. For example, buttons are not consistent or round like Steve Jobs would want. Not every link opens a new tab. Not every image shows the correct content in PodCasts. 

Have fun and make the player more productive and excitive. Make the site more readable.

Nice roundable buttons like Apple.

**Sliced into four sub-PRs.** Progress as of 2026-05-19:

- **37A — Pill-button system** ✅ shipped on PR #128. Apple-style pill `border-radius: 9999px` everywhere, single `.btn-primary` / `.btn-secondary` / `.btn-danger` base rule (was: ~12 distinct radius values across the file), iOS-style `:active { transform: scale(0.97) }` press feedback, 3px coloured focus ring.
- **37B — Link-target audit** ⏳ pending. External `<a>` → new tab; internal → same tab. Spec already exists from STUFF #19; this slice just enforces it everywhere.
- **37C — Podcast cover-art correctness** ⏳ pending. Some podcasts show placeholder / wrong art; rerun iTunes Search lookup for misses.
- **37D — Player + readability** ⏳ pending. Larger play button, speed-preset chips, body-copy line-height + max-width pass.

## [x] 39. Header

Can you change the eader to only show the optioms when logged in / out

**Shipped on PR #130.** Anonymous header is now logo + Sign in / Sign up + theme toggle; full nav (Articles / Bookmarks / Podcasts / YouTube / Sports / AI ▾ / Manage ▾ / 🔍 / Admin) + Bus icon + Refresh-all only render when signed_in?. 11 examples in `spec/header_signed_in_gate_spec.rb`.

## [x] 40. Deployment

Is this the most deployment process we can make to make sure:

- no deployment downtown with a new release
- quick new releaase

As we are have containers, are using Digital Ocean and their managed services, is there a better way? I'm used to AWS ECS which feels cleaner.

Please analyze.

Won't do.

## [x] 41. AI

AI is the current FAD. Can we have AI things to the users?

Won't do.

## [x] 42. Money

How do we make a little bit of money for this application? People use it. Advertisers want it. We want it useful and NOT in the user's face.

Constraint: the homepage tagline is "no tracking, no algorithmic agenda" — programmatic ad networks (Adsense, Carbon, pixel-based attribution) are out. Goal is "cover the $32/mo infra + future Anthropic API spend," not "build a business."

Won't do.

### Phased plan (least → most intrusive)

- **42.1 — Voluntary tipping** ✅ shipped on PR #133 (live in v0.9.2+). Buy Me a Coffee footer link gated on `BMC_HANDLE` env var; dev / unconfigured-prod builds omit the link cleanly. Opens in a new tab + `rel="noopener noreferrer"` so the BMC checkout doesn't dump the user out of the app. **Operator step remaining**: sign up at buymeacoffee.com, drop `BMC_HANDLE=your-slug` into `/opt/app/.env`, redeploy — link goes live in prod immediately.

- **42.2 — Free + Pro tier** (when user base hits ~20)
  - Free: all current features with the existing `LLM_USER_DAILY_TOKEN_BUDGET` (200k tokens/day).
  - Pro ($3-5/mo): higher LLM budget (1M+ tokens/day), custom Claude triage prompts, Opus instead of Sonnet for chat.
  - Aligns variable cost (Anthropic API) with variable revenue. No ads needed.

- **42.3 — Curated single-sponsor slots** (at ~100 users)
  - 1-2 hand-picked "Sponsored" items per day on /feeds, clearly labeled + dismissible.
  - Sponsor slot in the digest email (when email shipping happens).
  - Manually negotiated; no programmatic ad networks.

- **42.4 — Podcast 15s pre-roll** (once daily podcast listeners hit ~50)
  - Single sponsor per week, stitched as a static MP3 ahead of `audio_url` playback in the global player.
  - Preserve the publisher's own ads — just add one of yours up top.

### Not doing

- **Programmatic display ads** (Adsense / Carbon) — pixel tracking + algorithmic placement contradicts the no-tracking promise on /.
- **Mid-roll ads inside articles** — too intrusive.
- **Required paywall for AI features** at the free tier — the "magic" needs to be reachable to drive sign-ups.
- **Data licensing** of reading trends — too small to be valuable, and even anonymized it smells off.

## [x] 43. Filter Feeds

Filter Feeds on the /filter page doesn't work. Please fix.

(Note: there is no `/filter` route — the filter UI lives on `/feeds` via `public/feeds-filter.js` from STUFF #27. The bug investigation paused mid-session; if it still mis-fires in prod, reproduce + capture which input/chip doesn't filter rows.)

**Shipped.** Root cause was deeper than the original "deactivate doesn't work" report: `init()` was attached to both `DOMContentLoaded` AND `turbo:load`, and Turbo 8 fires *both* on a full page load. That double-wired every chip in [public/feeds-filter.js](public/feeds-filter.js) — each click ran the handler twice, the second pass saw `wasActive=true` and reset the active state back to "All", so clicking any chip appeared visually dead. Fix: a `data-filter-wired` sentinel in `wireBar` makes the wiring idempotent; the chip rows now respond on the first click. Same PR also lands the toggle-off fix originally targeted by this item (clicking the active non-All chip now switches back to "All" instead of being a silent no-op). 5 lockdown specs in [spec/feeds_filter_chip_toggle_spec.rb](spec/feeds_filter_chip_toggle_spec.rb).

The Turbo 8 double-fire is a class of bug worth watching for elsewhere — any `init()` attached to both events without an idempotency guard has the same shape. Other modules in [public/](public/) that wire on both events should be audited next time we touch them.

## [x] 45. Sports team follow management

Surfaced during the prod cutover: a freshly-signed-up user can't follow Eagles / Sixers / Union etc through the UI. The 4 hardcoded follows in `seed_sports_data.rb` were for user 1 only; new users see no scores at all on /sports.

Need: a management page (under Manage ▾) where users browse the team catalog grouped by league and toggle follow/unfollow per team. After follow, the team's recent schedule + results should sync within ~30s (not "next nightly run" — which itself isn't scheduled yet, see follow-up gap below).

**Shipped together (one PR):**

- `Providers::ESPN.teams_for_league(sport_path:)` — fetches the full roster from ESPN's `/<sport>/teams` endpoint and normalises to the `SportsTeamsStore.upsert` shape. Defensive empty-on-failure pattern like the other ESPN methods.
- `scripts/seed_sports_data.rb` extended to bulk-fetch NFL / NBA / MLS rosters when `SEED_FULL_CATALOG=1` (default). Rugby + FIFA skipped — their `/teams` endpoints return tournament-roster shape that doesn't match.
- `SportsTeamFetchWorker` (Sidekiq) — pulls a single team's schedule from ESPN and upserts into `sports_matches`. Enqueued from the new follow route so scores appear within ~30s of clicking "+ Follow".
- `GET /sports/manage` page — team grid per league with follow/unfollow toggle. Green accent + "✓ Following" outline pill on currently-followed teams; "+ Follow" solid pill on unfollowed.
- `POST /sports/teams/follow` + `/unfollow` — mirror the existing player follow/unfollow routes.
- "Sports" entry added to the Manage ▾ dropdown alongside Feeds + Tags.

**Operator step after merge + deploy**: SSH the Droplet and run `docker compose run --rm app make seed-sports-data` to populate the full catalog. Existing user 1's follows survive (idempotent upsert).

**Follow-up gap (closed)**: recurring sport-sync now runs nightly at 04:00 UTC via `SportsSyncWorker` + sidekiq-cron (`config/sidekiq_cron.yml`). Same PR adds hourly `RefreshAllFeedsWorker` so articles / podcasts / YouTube also stay fresh without the operator clicking "Refresh all". The `scripts/sync_sports.rb` body was extracted into [app/sports_sync.rb](app/sports_sync.rb) so the worker and the manual `make sync-sports` entry point share one code path. **Update**: hourly cron verified firing in prod on v0.13.0 deploy (00:00 UTC tick imported across all subscribed feeds); the header "Refresh all" button was removed in a follow-up PR — `POST /refresh/all` route stays for the per-feed buttons on `/feeds`, the admin cache page, and scripted-ops usage.

## [x] 46. /sports/tennis autosyncs on page load

Surfaced from prod (2026-05-18): `/sports/tennis` rendered empty because the `sports_players` table had never been synced on the Droplet. Even after a manual sync, ATP/WTA rankings would go stale within a week.

**Shipped on PR #136 (v0.9.5).** Opportunistic ESPN refresh on page load: when the last sync for a tour is > 12h old (or there's no data at all), the route calls `Providers::ESPN.tennis_rankings` inline and upserts. Adds ~1s to the first request after the TTL window; cached for everyone after. ESPN errors are caught + logged, never raised — the page still renders whatever's in the DB.

The per-tour fetch + slugify + upsert dance moved from `scripts/sync_sports.rb` into `SportsPlayersStore.refresh!(tour:)` + `refresh_if_stale!(tour:)` + `tennis_player_slug(name)` so the route AND the cron share one code path. 9 examples in `spec/sports_tennis_autosync_spec.rb`.

`?skip_refresh=1` bypasses the inline refresh (used by the empty-state spec + manual debugging).

**Related gap that's still open**: a similar autosync for the `/sports` team-score tiles. The eager sync from #45's follow-route covers freshly-followed teams; existing follows still need a recurring tick (or the same on-page-load pattern). Captured under #45's "Follow-up gap" note above.

## [x] 47. SQLite3

Are we done w SQLite3? If so, can you develop a plan to remove it from the codebase as well as CI.

**Shipped.** PG was the only production backend since Phase 5; SQLite was kept only for dev/test ergonomics. With the suite already green on PG via the CI matrix, dropping the second backend cuts CI in half and removes the adapter abstraction throughout the codebase.

What landed:
- `gem 'sqlite3'` removed from Gemfile + Gemfile.lock; `Database.adapter` / `Database.path` / `MIGRATIONS_DIR_SQLITE` deleted. `app/database.rb` shrank from ~165 LOC to ~95.
- 25 SQLite migration files in `db/migrations/` deleted (PG runs from the consolidated `db/migrations-postgres/` baseline).
- `scripts/dump_sqlite_to_postgres.rb` + its spec retired (one-shot tool, used during cutover).
- All `if Database.adapter == :postgres` branches in stores hoisted; SQLite arms deleted.
- `rescue SQLite3::ConstraintException, PG::UniqueViolation` → `rescue PG::UniqueViolation` (and similar). `raise SQLite3::ConstraintException` in `FeedsStore.add` → `raise PG::UniqueViolation`.
- `spec_helper.rb` now requires `TEST_DATABASE_URL`; in-memory SQLite fallback gone.
- CI matrix `[sqlite, postgres]` → single `postgres` job; cuts wall-clock CI time roughly in half.
- Dockerfile drops `libsqlite3-dev` + `libsqlite3-0` + the `/app/data` volume; docker-compose drops `app_data` volume and makes `DATABASE_URL` required.
- `Database.date_sql` simplified to a single-line PG expression (no per-backend switch).
- Admin overview's "DB path / size on disk" rows now show "PostgreSQL (managed)" + `pg_database_size(current_database())`.
- `pg_adapter.rb` commentary cleaned up — no longer needs to frame itself as a SQLite-compatible facade.

Suite: 1342 / 0 on PG.

## [x] 48. Admin Pages

Simple analytics:

Make a proposal to add simple analytics to the admin area:

- new users over time
  - subpage that lists users
- last fourteen days of pageviews
  - aggregted across entire site
  - by section (articles, podcasts, youtube)
  - average time in each section

Admin Simple Auth:

For now, let's create the admin page by simple auth. I put credentials in the .env file. Be sure to include in our releases to production.

**Shipped across two PRs:**
- Analytics half — PR #140 (STUFF #48.1): `/admin/analytics` (90-day pageview chart + section breakdown + new-users-per-day) and `/admin/users` (user list with last-seen + LLM cost). Pageviews are recorded server-side by `RequestLogMiddleware`; 90-day retention sweep runs opportunistically.
- Auth half — spawned its own item as **#49** (admin Basic Auth gate, PR #141). See #49 below for the full changelog.

## [x] 49. Admin Basic Auth gate

Surfaced from "did we do admin simple auth?" — answer was no: `/admin/*` was gated only by the WebAuthn sign-in wall, so any signed-in user could see other users' usernames + last-seen-at + LLM costs.

**Shipped on PR #141.** HTTP Basic Auth over `/admin/*` + `/api/admin/*`:

- `ADMIN_USERNAME` + `ADMIN_PASSWORD` env vars in `/opt/app/.env`.
- `Auth.authorized_admin?(env)` parses the `Authorization: Basic <base64>` header + constant-time compares against the configured creds via `Rack::Utils.secure_compare`.
- Sinatra `before` filter on `Auth.admin_path?(path)` halts 401 + `WWW-Authenticate: Basic realm="Admin"` when credentials are absent / wrong.
- **Fail-closed**: an unset / empty pair means /admin is 401 for everyone (including the operator). Forces an explicit opt-in rather than letting a missing-env-var bug silently open the admin pages.
- Stacks on top of the existing WebAuthn sign-in wall — anonymous visitors still bounce to /sign-in first; signed-in users hit the Basic Auth challenge as a second gate.
- 30 examples in `spec/admin_gate_spec.rb` covering parser edge cases, path-matcher set, gate pass/fail behaviour, and the logout/re-login flow.

**Turbo prefetch gotcha** — the global nav has an `<a href="/admin">` link visible on every page. Turbo 8 hover-prefetches links by default, so mousing over the "Admin" nav link silently issued a GET /admin which 401'd + set `WWW-Authenticate`, causing the browser to pop the Basic Auth prompt on unrelated pages like /articles. Fix: the layout tags that single anchor with `data-turbo-prefetch="false"`. All other admin links live inside admin views (only rendered post-auth), so they're not affected.

**Logout button (`POST /admin/logout`)** — Basic Auth has no protocol-level logout; the browser caches credentials per-origin until the user closes the tab. Workaround via session flag:

- "Log out of admin" button on `/admin` posts to `/admin/logout`, which sets `session[:admin_logged_out] = true` and redirects back to `/admin`.
- The gate, when it sees the flag set, 401s even when valid cached credentials are present. The `admin_denied.erb` page detects this branch and renders a "Logged out" variant with a "Resume admin" link.
- `GET /admin/login` is the only path exempt from the gate — clicking "Resume admin" hits it, the route clears the flag, redirects to `/admin`. Cached browser creds then re-authenticate transparently.
- For true credential clearing (e.g. before handing the laptop to someone else), the page explicitly tells users to close all tabs of this origin or use a private window. Honest about the limit.

**Operator follow-ups**: drop `ADMIN_USERNAME=...` + `ADMIN_PASSWORD=...` into `/opt/app/.env` on the Droplet, then `make deploy`. Until those are set in prod, /admin is unreachable.

## [x] 50. Beauty Pass

Let's do a beauty pass in on PR. Don't commit and open a PR until I view and approve. Do things in phases.

- I zoom in to 125% to have a good font size that is easy to read. Update the default accordingly.
- on the /articles page, if the article doesn't have a picture, it looks indented with items that do have pictures. Can you align the "columns" so they look the same with or without a picture.
- on the /articles page, can you add a summary or opening set of sentences to each to give the user more context of the article.
- on the /artices page, when you click ON a filter ... it says on and you can't turn it off by clicking the button to deactivate it. Please fix.
- I love the look of the /podcasts page with the image of the podcast. On the /youtube page, can you do something similar to make it more visual. 
- can you move the search button to behind admin and before bus
- we need to change the home page link in the header from Tech Feed Reader to Feeder
  - is there a free icon we can use to bruce this up: <icon> Feeder
    - feel free to consider animals or other items that represent feeding: pics, cows, etc.
- in dark mode, prior used links are hard to read I think b/c of the color: blue and purple ... can you try something else
- in dark mode, add a little frost layer on the background ... user can still make out the image, but it doesn't dominate the main content on the page

**Shipped.** Sequenced as six phases, each manually verified before moving on:

1. `/articles` state-filter chips toggle off on second click; Search nav moved out of the section-nav to the icon row (Admin → Search → Bus).
2. `html { font-size: 125% }` baseline — default reading size now lands where you previously had to zoom.
3. Every `.news-item` shares a 3-column grid (thumb / content / utility) so rows with and without thumbnails line up at the same x-position. Every card gets a 2-line summary preview pulled via `skim_summary_for` (LLM → extractive → content excerpt). Footer row puts source · time · reading-time on the left and ★ / tags / 👍 / 👎 on the right.
4. `/youtube` gains a Recent-videos grid mirroring `/podcasts`' recent-episodes panel (16:9 hqdefault.jpg thumbnails, ▶ overlay on hover). Subscribed-channel cards now click through to the latest video; cover-art fallback chain is `feed.image_url → latest-video hqdefault`. Secondary links "All videos →" + "↗ Channel" preserve the channel-detail page and the off-site YouTube link.
5. Brand renamed "Tech Feed Reader" → "Feeder" everywhere (header logo, document title, footer, `/about` body). Header gets a random animal emoji per page render from a 10-emoji pool (🐦 🦜 🐤 🦉 🦅 🦆 🦢 🐄 🐷 🐝) — bird-feeder pun first, barnyard for variety.
6. Dark mode polish: background image moved to a fixed `body::before` and gets `filter: blur(10px) saturate(0.75) brightness(0.8)` plus a 0.40-opacity scrim — frosty texture, image still legible, foreground unaffected. Visited-link color set to soft #9ab5d8 (avoids the browser-default purple the user found hard to read).

## [x] 51. Sidekiq Basic Auth

Can you use the same Basic Auth credentials for Admin for Sidekiq?

## [x] 52. Sports Manage

I just noticed that the sports manage page only has leagues that I care about. Sports is much wider than me, so we need to expand for popular world wide and popular leagues and teams. For example:

- baseball, including leagues in say Japan
- WNBA
- Tennis: WTA, ATA, etc.
- Cricket
- Soccer, particularly South America
- Gold
- Formula 1
- NASCAR
- Badminton
- Horse Racing
- etc.

Make it easy to navigate to each area and browse feeds that can be added to a user's account. We may need a drill down. Drill down to add leagues, teams, and players.RTFGApp

Use logos, etc.

I don't know Africa or the Middle East, make sure they are represented.

Women leagues should be highlighted and promoted.

Sports is not just a US things. It is Global, let's be sure to 

**Shipped across three PRs:**

- **PR1 — Foundation** (#145): new `app/sports_catalog.rb` hand-curated module + sport-first `/sports/manage` browsing (sport → league → team drill-down). Seeded with 7 sports, women's leagues equal-weight (NBA + WNBA, MLS + NWSL, EPL + WSL, etc.), global representation (CAF, Copa Libertadores, AFC Asian Cup, FIFA M + W World Cup). Follow flow upserts catalog teams to the DB on demand so the live-scores pipeline keeps working off the same rows.
- **PR2 — Breadth** (#146): 5 new sports (🏏 Cricket, ⛳ Golf, 🏸 Badminton, 🐎 Horse Racing, + Motorsport NASCAR/IndyCar/WEC) + soccer global depth (Bundesliga, Serie A, Saudi Pro League, Brasileirão, J1 League, WE League, Egyptian Premier League — plus Frauen-Bundesliga + Serie A Femminile for women's). 16 new leagues; +512 LOC data-only.
- **PR3 — Feed wiring + player chips** (#147): `SPORTS_LEAGUE_FEEDS` bridge in `app/feed_catalog.rb` binding leagues → curated RSS URLs. New "News + podcasts" panel under each team grid with one-click `POST /sports/feeds/subscribe`. 16 new feed entries in `FeedCatalog::CATALOG` covering cricket / baseball / golf / motorsport / horse-racing / WNBA / women's + European + African soccer. Notable-player chips under top teams (Eagles, Sixers, Real Madrid, Bayern, IPL Mumbai/Chennai, F1 works teams). 6 new feed categories (`:cricket :baseball :golf :motorsport :badminton :horse_racing`).

Final tally: 12 sports, ~60 leagues, ~250 teams/players. Suite: 1356 / 0.

**Deferred to a follow-up PR**: player-click navigation (catalog → DB player upsert mirroring the team upsert from PR1); logos beyond the 🏟 fallback; NPB + KBO + badminton RSS bridge entries (couldn't find stable English-language URLs in this pass).

**#52.1 follow-up — player-click navigation — shipped.** Mirrors the catalog-team-on-demand upsert pattern from PR #145. New helpers in [app/main.rb](app/main.rb): `ensure_catalog_player_in_db(team_slug, name)` upserts a `sports_players` row with composite slug `"{team_slug}-{name_slug}"` and `source_provider='catalog'`; `ensure_catalog_player_by_slug(slug)` walks the catalog matching a team-slug prefix and resolves the player. `GET /sports/player/:slug` falls back to that resolver when the DB miss, then renders the existing player view. The view ([views/sports_player.erb](views/sports_player.erb)) now branches on `@player['tour']`: tennis players still get their flag / rankings / stat-cards / ESPN profile; catalog players see "Notable player on **TEAM** · Sport" with a back-link to the team's manage page, and the tennis-specific UI hides. Player chips in [views/sports_manage_league.erb](views/sports_manage_league.erb) are now anchors with a subtle dotted-underline hover. 8 examples in [spec/catalog_player_upsert_spec.rb](spec/catalog_player_upsert_spec.rb) cover the upsert, idempotence, view branching, 404s for unknown slugs, the `slugify` helper (accent stripping + edge-trim), and the chip-link render.

**#52.2 follow-up — sport-emoji fallback — shipped (pragmatic).** Catalog teams without an `image_url` rendered as 🏟 (generic stadium) on `/sports/manage/<sport>/<league>`. Swapped the fallback for the sport's own emoji (`@sport[:emoji]`): NFL → 🏈, NBA → 🏀, EPL/La Liga/MLS → ⚽, IPL → 🏏, F1 → 🏎️, etc. Every sport in [app/sports_catalog.rb](app/sports_catalog.rb) carries its own emoji at the sport level, so the swap is a one-line view change with no per-team data work. Note `/sports` score tiles and `/sports/team/:slug` headers already use per-team emojis from [app/sports_teams.rb](app/sports_teams.rb) (🦅 Eagles, 🥍 Lions, etc.) for the structured-data teams the user has followed, so this fix lands exactly where it was needed.

**Real per-team logos remain a future task** (not in this PR): the catalog currently carries no `image_url` for any of the ~250 teams. Filling them in needs a sustainable source — Wikipedia/Wikidata via a one-shot scrape into the catalog, or hand-curation. The visual benefit is real but the maintenance cost (broken hotlinks, rebranding, etc.) is non-trivial. Deferred until someone has time to do the Wikidata pass cleanly.

**#52.3 follow-up — NPB / KBO / BWF RSS bridges — shipped.** Original sweep noted "couldn't find stable English-language URLs in this pass." Re-tried with `curl` verification; landed five new catalog entries:

- **BBC Sport — Baseball** (`feeds.bbci.co.uk/sport/baseball/rss.xml`) — worldwide baseball, regular NPB mentions around Japan Series.
- **MyKBO** (`mykbo.net/feed/`) — independent KBO-specific English coverage; daily recaps + standings + roster moves.
- **Yonhap News — Korean Sports** (`en.yna.co.kr/RSS/sports.xml`) — Korean sports overall (KBO + K-League + Olympics).
- **BWF Badminton — Official** (`bwfbadminton.com/news/feed/`) — World Tour + Championships + Olympics + Sudirman Cup.
- **Badzine** (`badzine.net/feed/`) — independent badminton journalism, interviews + tournament recaps.

Wired into `SPORTS_LEAGUE_FEEDS`: `npb` → BBC Baseball + ESPN MLB (fallback since dedicated English NPB feeds don't exist; ESPN MLB heavily covers Japanese players); `kbo` → MyKBO + Yonhap + BBC Baseball; `bwf-mens` + `bwf-womens` → BWF + Badzine. 9 lockdown specs in [spec/sports_league_feeds_bridge_spec.rb](spec/sports_league_feeds_bridge_spec.rb) — 2 per sport for the bridge bindings + 5 catalog-integrity checks confirming each new URL is registered (so `/sports/feeds/subscribe` doesn't 422 when a user clicks Subscribe).

**With #52.1 + #52.2 + #52.3 shipped, STUFF #52's three deferred follow-ups are closed.** Remaining sports work is real per-team logos (still deferred — see note above).

**Full NFL + NBA rosters — shipped (separate small PR).** The catalog originally had 5 NFL teams (Eagles + Cowboys + Chiefs + 49ers + Bills) and 5 NBA teams (Sixers + Celtics + Lakers + Warriors + Bucks) — enough for demo but a freshly-signed-up fan of any other team had no way to follow them through the UI. Backfilled the remaining 27 NFL + 25 NBA teams via the live ESPN `/teams` endpoint (canonical IDs, slugs, locations) so `/sports/manage/football/nfl` and `/sports/manage/basketball/nba` now show the complete league. Notable-player chips intentionally left empty for the new teams (player data changes too fast to maintain by hand; the original Eagles + Sixers entries' players stay because they were curated). 8 lockdown specs in [spec/nfl_nba_full_rosters_spec.rb](spec/nfl_nba_full_rosters_spec.rb) cover the full slug set + uniqueness of IDs and slugs.

## [x] 54. Tennis Rankings Page

- can you add a link from the Manage Sports Tennis page to this page to make it easy for users to follow players
- on the Tennis Rankings page, clicking the Follow / Like button from the player results in the page reloading ... to the top of the page. We did this before, can we make these types of calls AJAX throughout the site to keep the user where they are. Some of our pages are very long. So scrolling is not a good user experience.
- in general, we should have links from the manage pages to the pages where things happen
- also on the tennis rankings page, if the WTA player has a picture, it overlaps with the favorite star button from the ATP player. So you can click it. Please fix.

**Shipped.** Four concerns in one PR:

- **AJAX follow/unfollow on sports surfaces.** The four routes (`POST /sports/players/follow`, `/players/unfollow`, `/teams/follow`, `/teams/unfollow`) plus `POST /feeds/:id/feedback` now return `{ok, slug/feed_id, kind/direction, followed/weight}` when `Accept: application/json`. New [public/sports-follow.js](public/sports-follow.js) intercepts `form.js-sports-follow-form` submits via the *form's* submit event (more robust than click — fires regardless of trigger) and toggles button state in place. [public/feeds.js](public/feeds.js) gains a sibling handler for the per-row `+/−` weight buttons; the weight readout updates inline. No reload, no scroll loss.
- **Tennis navigation gap closed.** `/sports/manage/tennis` now shows a soft-blue callout linking to `/sports/tennis` (the player follow surface); each tennis league card retargets its click from the team grid (which doesn't exist for individuals) to `/sports/tennis#tour-{slug}` so ATP/WTA jump straight to the right section. Also adds an "ATP ↓ / WTA ↓" anchor TOC on the rankings page itself.
- **WTA picture overlap fix.** ATP/WTA tour tables previously sat in a 2-column grid (`minmax(420px, 1fr)`); long player names + cell-overflow caused the WTA photo column to bleed into the ATP follow-cell so the star was unclickable. Stacked vertically (single column) — each table gets the full content width.
- **Session-hijacking gotcha.** Rack::Protection's `:session_hijacking` fingerprints the session against User-Agent / Accept-Encoding / Accept-Language and silently clears the session if any change between requests. Browser `fetch()` calls normalised those headers differently than the initial WebAuthn sign-in, destroying the session for AJAX even though browser navigation worked fine. Excluded the protection (low-value heuristic, defeated by easy spoofing anyway). Cost was a totally broken AJAX-follow UX until I traced it.

**Specs**: +12 examples (8 in [spec/sports_follow_ajax_spec.rb](spec/sports_follow_ajax_spec.rb) for the four sports routes + JS lockdown; +1 JSON-branch example on the feed-feedback route). Full suite: 1384 / 0.

## [x] 55. Beauty Pass 002

- on the /feeds pqge, please remove the Refresh All button
- on the sports drill down pages, example /sports/manage/basketball/euroleague, the "Follow" and "Subscribe" buttons force a truncation of the first column. Instead of doing in two columns, do in two rows.
- on the topics pages, for example /topics/philadelphia, the individual elements are in two colums, with the link in the first colum. Instead of columns, format in two rows. The link is squooshed making it hard to read.

**Shipped on the same PR as #54.** Three minor visual cleanups:

- **`/feeds` Refresh-all removed.** Header button + its JS handler in [public/feeds.js](public/feeds.js) gone now that the hourly RefreshAllFeedsWorker cron fans out automatically. `POST /refresh/all` route stays (still used by `/admin/cache` + scripted ops).
- **Sports drill-down two-row layout.** `.sports-manage-team` (team grid) and `.sports-feed-card` (news+podcasts grid) switched from flex-row to two-row CSS grid: logo+meta on row 1, full-width action button (`+ Follow` / `+ Subscribe`) on row 2. The button no longer competes with the meta column for horizontal space; long team names no longer truncate.
- **Topic pages stacked rows.** [views/topic.erb](views/topic.erb) was reusing `.news-item` (designed for `/articles` with a 96px thumb column + right-side badges column), but topic rows have no thumb or badges — so the grid was crushing the title link into a sliver. New `.news-list-simple` modifier overrides the grid to `display: block` so each row stacks naturally (title → excerpt → meta), full width.

## [x] 56. Beauty Pass 003

On the artlce page, there's a section for "Related" articles. Like other elements throughout the site, it's hard to read because it is two columns, the first being the title. Can you refactor to having two rows instead of two columns.

**Shipped.** Same root cause as the topic-page fix in #55: the bare `<li class="news-item">` reuses the `/articles` 3-column grid (`thumb / main / badges`) without rendering thumbnail or badge children, which collapses the title into a narrow main column next to a wide auto-sized meta column. The `.news-list-simple` modifier added in #55 already overrides that — just needed to be applied here. Two 1-line ERB edits:

- [views/article.erb](views/article.erb) — `/article/:uid` Related section.
- [views/dashboard.erb](views/dashboard.erb) — `/admin/dashboard` "Recent unread" list (same pattern, you would have hit it next).

Audit verified no other instance of the bug — `/articles` and `/search` use the full grid; `/topics` was fixed in #55.

## [x] 57. Active Budgets

On the /admin/llm-quota page, the Active Budgets area elements are two skinny for the content. Instead of trying to put four items per row, can we do two items per row. Make them take up 1/2 the width.

**Shipped (bundled with the Refresh-all copy sweep).** The default `.stat-cards` grid is `repeat(auto-fit, minmax(160px, 1fr))`, which packs all four budget cards into a single row on wide admin screens — cramping the env-var names (`LLM_USER_DAILY_TOKEN_BUDGET` etc.) and the "rolling 24h" / "API-equivalent" subtitles. New `.stat-cards-pairs` modifier scoped to the Active Budgets div forces `repeat(2, 1fr)` so each card gets half the row width; collapses to a single column under ~640px so the hierarchy still reads on narrow screens. Other `.stat-cards` consumers (dashboard, dev-stats) keep the auto-fit grid unchanged.

## [x] 58. YouTube description formatting

On a YouTube article page, the text under the video almost always does look right. Links are formatted or clickable. The text is just a blob of letters and numbers. What format do you generally get that information? Any thoughts on how to make it more readable?

**Shipped.** Root cause: YouTube channels publish Atom feeds where each `<entry>` has the video description as **plain text** — URLs are bare, hashtags are bare, line breaks are `\n`. Our [app/feed_parser.rb](app/feed_parser.rb) runs that through `Sanitizer.sanitize_html`, which preserves it as-is (no `<br>`, no `<a>`). The article view then renders the result raw, so the browser collapses all whitespace and leaves the text unclickable — exactly the "blob of letters and numbers" the user described.

New helper [`format_youtube_description_html`](app/main.rb) escapes the text and runs a single combined regex that wraps three classes of inline markup:

- **`.yt-link`** — bare `http://` and `https://` URLs become `<a target="_blank" rel="noopener noreferrer">`, trailing punctuation (`.` `,` `;` `!` `?` `)`) stays outside the anchor so URLs read correctly.
- **`.yt-timestamp`** — `0:00`, `1:23`, `1:23:45` patterns become `<button data-seconds="N">`. [public/youtube-watch.js](public/youtube-watch.js) gains a delegated click handler that uses the IFrame API to `seekTo(seconds, true)` + `playVideo()` + scroll the iframe back into view. Lookbehind on the regex ensures `https://example.com/v1:2` isn't false-positive as a timestamp.
- **`.yt-hashtag`** — `#word` (only when preceded by start-of-string or whitespace, so `issue#123` doesn't match) links to YouTube's search-by-hashtag URL.

Line breaks survive via `white-space: pre-line` on the `.article-youtube-description` wrapper — no need to inject `<br>`. Styled to match the rest of the article body: subtle blue dotted-underline links, soft-blue pill timestamps that hover into a stronger accent. Branch in [views/article.erb](views/article.erb) opt-ins YouTube articles only (via `youtube_video_id(@article)`); non-YouTube articles render `content_html` raw as before.

10 lockdown specs in [spec/youtube_description_format_spec.rb](spec/youtube_description_format_spec.rb) cover HTML escaping, URL anchor attributes, trailing-punctuation trimming, MM:SS / HH:MM:SS conversion, URL-vs-timestamp disambiguation, hashtag matching rules, and a combined BBC Earth fixture.

## [x] 59. Summaries on Article Page

Get ride of Re-Summarize and Summarize by Claude on the artice pages.

**Shipped.** Removed the two action buttons ("Re-summarize (extractive)" and "Summarize with Claude") + the `.summary-actions` wrapper from [views/article.erb](views/article.erb). The Summary section itself stays — the extractive sentences (generated at import time) still render inline below the heading, and any previously-cached Claude summary still appears with its blue accent border. Dependencies untouched:

- **Extractive generation at import** still runs (`Summarizer::Extractive`) and feeds the `summaries.extractive` column.
- **Skim previews** on `/articles`, `/search`, `/triage`, `/sports/team/*`, `/podcasts`, `/whats-on` — `skim_summary_for` still cascades `llm → extractive → content_text excerpt`, so those 2-line previews keep working.
- **Daily digest Claude summarization** at `/digests/:id` is a separate code path and untouched.
- **`POST /article/:uid/summarize` + `.../summarize/llm`** routes left intact so curl / scripted clients keep working. UI just doesn't expose them anymore.

Also deleted [public/article-summarize-form.js](public/article-summarize-form.js) (the "Summarizing… (5–15s)" loading-state hook for the removed button) and its `<script>` tag in article.erb — no other surface uses it.

## [x] 60. Welcome page drift sweep

After the last refresh in #53, six claims on the logged-out home + about pages had drifted from reality. Audit + fix:

- `views/home.erb` "One inbox" card: `90+ curated feeds` → `100+` (after #52.3 added 5).
- `views/home.erb` Sports card: rewritten to mention every NFL + NBA team (per #157), NPB + KBO baseball (per #52.3), and notable-individual-player follow chips (per #52.1). The old text only mentioned "tennis players" individually.
- `views/home.erb` narrative: "Tech Feed Reader inverts that" → "Feeder inverts that" (brand rename from #50, finally caught up); "pulls every feed every ten minutes" → "the hourly refresh cron pulls every feed automatically" (since #150's sidekiq-cron).
- `views/about.erb` Ingest bullet: "every 10 minutes" → describes the RefreshAllFeedsWorker fan-out + per-feed worker pattern.
- `views/about.erb` Sports bullet: `~250 teams` → `~300 teams`; mentions notable-player click-through chips.

Surgical changes (one paragraph per item), no new sections. Triggered by the standing follow-up rule from #53 ("always review the welcome page after a key new feature").

## [x] 61. Broken Links

I've noticed broken links in content that we import. Perhaps we should add a filter to test links and remove broken ones or fix them if we can. Perhaps some are local links that can be updated to the content source.

Also, add the ability to run via make a directive to fix the entire article database.

**Shipped.** Two parts:

**At import — link absolutization.** Publisher RSS often emits in-domain links as relative paths (`/category/foo`, `author/bar.html`) or protocol-relative (`//cdn.x.com/img.jpg`). When rendered under `feeder.tmoneystuff.com` those resolve against the wrong origin → 404 or wrong image. New `LinkAbsolutizer` Loofah scrubber in [app/sanitizer.rb](app/sanitizer.rb) rewrites every relative `<a href>` and `<img src>` (also `<source src>`) to absolute using `URI.join(base_url, href)`. Anchors (`#section`), `mailto:`, `tel:`, `javascript:`, and `data:` URLs are skipped. Defensive `rescue` around `URI.join` so malformed publisher HREFs don't crash the import. `Sanitizer.sanitize_html` gains a `base_url:` kwarg (backward-compatible — defaults to nil, in which case the scrubber doesn't run). Both call sites updated: `app/feed_parser.rb` passes the entry URL, `app/providers/readability.rb` passes the fetch URL.

**Retroactive fix — `make fix-article-links` + daily Sidekiq-cron.** Logic lives in [app/article_link_scrubber.rb](app/article_link_scrubber.rb): iterates every article with non-empty `content_html` AND `content_scrubbed = FALSE`, re-sanitizes with the article's own URL as the base, then bumps `content_scrubbed = TRUE` so subsequent runs skip the row entirely (no re-parsing). Empty-content rows get a flag-only bump in a final pass so the unscrubbed pool drains to zero. New migration `003_articles_content_scrubbed.sql` adds the column (`BOOLEAN NOT NULL DEFAULT FALSE`); new imports in `ArticlesStore.import` set it to `TRUE` on insert since the scrubber already ran.

Two entry points share the module: [scripts/fix_article_links.rb](scripts/fix_article_links.rb) (manual one-shot, env flags `DRY_RUN=1` / `LIMIT=N` / `VERBOSE=1`) and a new `FixArticleLinksWorker` registered in [config/sidekiq_cron.yml](config/sidekiq_cron.yml) at `45 4 * * *` UTC (daily 04:45, slotted between the nightly sports sync at 04:00 and the next hourly feed refresh at 05:00). Steady-state daily run is a millisecond no-op; the WHERE-clause filter keeps the query cheap regardless of total article count. The operator can also trigger it on demand from the Sidekiq web tab.

Dev-DB pass (20,628 articles): 1,671 had relative URLs rewritten (Engadget `/category/...` and `/author/...` paths, Schneier blog cross-links, 404media internal links, the `tomscii.sig7.se` electronics post with 24 images + 22 cross-refs); 5,440 already-absolute (flag bumped); 3,507 skipped (opaque GUID URLs from older podcast feeds — flag bumped); 762 empty-content (flag bumped). Final remaining unscrubbed: 0.

**Not in scope** — HTTP HEAD probing for dead external URLs. Detection is expensive (one request per link), false-positive-prone (sites return 403/405 to bots, return 200 with soft-404 bodies), and remediation is ambiguous (remove the anchor? replace with text?). The absolutize fix addresses the most common breakage; dead-link probing left as a future task if it becomes a real problem.

**Specs**: +9 examples in [spec/sanitizer_spec.rb](spec/sanitizer_spec.rb) cover root-relative, path-relative, protocol-relative, already-absolute, anchor/mailto/tel skip, `<img src>` rewrite, malformed-URI tolerance, no-op-when-base_url-empty, and idempotence. Suite: 1428 / 0.

## [x] 62. Legal

As we get ready for launch, we need to probably update the site for legal complance. For example, a privacy statement and anything else you feel necessary. We'll probably need to add links to the footer for these items.

**Shipped — two new public pages, both linked from the layout footer.**

[views/privacy.erb](views/privacy.erb) is a plain-language summary, factually pinned to the actual data model: what we store (account, subscriptions, reading state, articles + retention window, sports follows, structured request log), what we don't (no email, no real name, no behavioural analytics, no third-party cookies), what we send to which third party (Anthropic for triage / summaries; DigitalOcean for hosting; iTunes / ESPN / Picsum for unauthenticated public lookups), retention windows, and the user's in-app rights (delete via `/account`, passkey management, recovery-code regen, data export marked as not-yet-implemented).

[views/terms.erb](views/terms.erb) covers as-is provision, acceptable use (no industrial scraping, no abuse of LLM budgets, no auth-wall bypassing), termination (you can leave any time; we can suspend on abuse), the warranty disclaimer + liability cap, and change-of-terms semantics. Includes a clearly-marked `[Operator: insert governing-law state ...]` placeholder in the Governing law section so it's obvious what needs to be filled in before launch.

Both pages reachable without sign-in: `/privacy` + `/terms` added to `Auth::PUBLIC_PATHS`. Public routes in [app/main.rb](app/main.rb) mirror the existing `/about` shape. Footer links wired between the existing About + shuffle-background entries. 4 specs in [spec/legal_pages_spec.rb](spec/legal_pages_spec.rb) cover the route 200s, key-section presence, public-path registration, and footer linkage.

**Governing law filled in**: Pennsylvania (state and federal courts in Philadelphia County).

**Contact path — form + admin queue.** The repo is private (so an "open an issue" link goes nowhere) and a published email address is a spam magnet. Solved with a third path:

- Public `/contact` form ([views/contact.erb](views/contact.erb)) — body required, subject + reply-to optional, hidden honeypot field that bots auto-fill (server pretends success on honeypot match so the bot's heuristics don't iterate). Signed-in submitters get `user_id` attached automatically for triage context; anonymous submissions accepted with a clear "we won't know who you are unless you tell us" note.
- New `support_messages` table (migration `004_support_messages.sql`) with `status` (`new` / `reviewed` / `responded`) + `admin_note` for private operator triage.
- Admin queue at `/admin/support` ([views/admin_support.erb](views/admin_support.erb)) — newest-first, status-filter chips, status-coded left border (orange = new, blue = reviewed, green = responded), inline expand-to-update form for status + admin note. Linked from `/admin` index.
- Footer link added between Terms and shuffle-background; `/contact` registered in `Auth::PUBLIC_PATHS`. Both `views/privacy.erb` and `views/terms.erb` Contact sections updated to point at the form (was: "open an issue on the project's repository").

13 specs in [spec/contact_form_spec.rb](spec/contact_form_spec.rb) cover the public-paths registration, GET/POST shape, the empty-body 400, honeypot silent-success, max-length trimming, blank-fields-as-nil, signed-in user_id attachment, admin list + filter, and admin update. **Suite: 1449 / 0.**

## [x] 63. Pre-launch readiness bundle

Shipped together as the "ready to announce" punch list:

- **`/robots.txt`** — disallows the user-scoped surface (`/admin/`, `/api/`, `/account/`, `/article/`, `/articles`, `/bookmarks`, `/digests`, `/feeds`, `/podcasts`, `/youtube`, `/sports`, `/search`, `/tags`, `/topics`, `/triage`, `/whats-on`, `/bus`, `/refresh/`). Sitemap reference. Public pages crawlable.
- **`/sitemap.xml`** — public-only (`/`, `/about`, `/privacy`, `/terms`, `/contact`, `/sign-up`, `/sign-in`). Daily lastmod.
- **OG / Twitter card meta** — added to [views/layout.erb](views/layout.erb) head. `og:title` / `og:description` / `og:image` (the dashboard hero), `twitter:card=summary_large_image`. Per-page override available via `@og_description`. Canonical URL on every page. Shared links on Mastodon / Slack / iMessage now render a preview card.
- **Branded 404 + 500 pages** — [views/not_found.erb](views/not_found.erb) for unknown routes; [views/error_500.erb](views/error_500.erb) for unhandled exceptions. The 404 handler is JSON-aware (`/api/*` paths + `Accept: application/json` get a JSON shape; HTML clients get the branded page) AND respects pre-set bodies so per-route `halt 404, erb(:article_not_found)`-style surfaces don't get stomped.
- **Tighter rate limits** — `/api/auth/register/*` capped at 3 per 30 min per IP (was 20/5min through the generic auth rule); `POST /contact` capped at 5 per 10 min. Defense-in-depth on top of the honeypot.
- **`/admin/status`** — single operator page stitching `/health` (DB / Redis / Sidekiq dots) + Sidekiq stats (enqueued / retries / workers) + sidekiq-cron job state (name / class / schedule / last_enqueue_time) + corpus counts (users / feeds / articles / articles-last-24h / new support messages). Linked from `/admin` index. Reuses existing `check_db` / `check_redis` / `check_sidekiq` / `sidekiq_stats` helpers; no new dependencies.
- **`GET /account/export.json`** — fulfils the privacy-policy promise to let a user download their data. New `AccountExport` module dumps every per-user table (`users`, `feeds_users`, `read_state`, `tags`, `feed_feedback`, `mute_rules`, `sports_follows`, `triages`, `digests`, `webauthn_credentials`, `recovery_codes`, `support_messages`) as JSON. WebAuthn public keys are base64-encoded; recovery-code hashes are redacted (HMACs aren't reversible). `Content-Disposition: attachment` so the browser prompts to download. Linked from `/account` as a `Download my data (JSON)` button. `/privacy` updated — the "Export your data — not yet implemented" line now points at the working endpoint.
- **Backup audit** — DO Managed PG dailies confirmed working (6 retained backups, May 17 → May 22, sizes growing). The legacy `tech-feed-reader-backups` DO Spaces bucket from the pre-Phase-5 SQLite era is empty; opted to leave it idle ($5/mo, no current writer) rather than wire up an off-account `pg_dump → Spaces` pipeline now. Decision parked for later if the user base grows enough to warrant off-account redundancy.

12 new examples in [spec/pre_launch_readiness_spec.rb](spec/pre_launch_readiness_spec.rb) cover robots.txt, sitemap.xml, OG meta, branded 404, RateLimiter rule shape for register + contact, `/admin/status` sections, `/account/export.json` envelope + recovery-code redaction, and the privacy-page update. **Suite: 1461 / 0.**

## [x] 64. rack-mini-profiler

Can you research if rack-mini-profiler can be used in this Sinatra app while running in development mode? This might help when debugging.

**Shipped.** Added `rack-mini-profiler` (~> 3.3) + `stackprof` to the Gemfile under `group :development`, so neither is bundled into the production image. Wired in `app/main.rb` via `configure :development do; require 'rack-mini-profiler'; require 'stackprof'; use Rack::MiniProfiler; end` — the middleware loads only when `RACK_ENV=development` (test + production paths are untouched). Auth wall allowlists the `/mini-profiler-resources/` prefix in `Auth::PUBLIC_PREFIXES` so the badge's JS/CSS load without bouncing to `/sign-in`. The gem auto-instruments the `pg` gem at require-time, so per-SQL-query timing shows up in the badge drill-down with no extra wiring — useful on `/articles`, the For-You ranker, and the topic-cluster page. `stackprof` enables the `?pp=flamegraph` URL trick for sampling-profile flame charts when timing alone isn't enough. `Rack::MiniProfiler.config.enable_advanced_debugging_tools = true` unlocks the advanced `?pp=` views (memory info, GC stats, exception traces) that the gem keeps gated by default. **SQL instrumentation**: the gem's pg-adapter patch is auto-detected only in Rails apps (gated on `patch_rails?` in [lib/patches/sql_patches.rb](https://github.com/MiniProfiler/rack-mini-profiler/blob/v3.3.1/lib/patches/sql_patches.rb)), so we force-load it with `ENV['RACK_MINI_PROFILER_PATCH'] ||= 'pg'` set BEFORE `require 'rack-mini-profiler'` — otherwise the badge shows total request time but no per-query breakdown, which defeats the point on `/articles`, the For-You ranker, and the topic-cluster page. SQL captured for AJAX/API calls flows through too: mini-profiler stitches per-AJAX profile ids into the initiating page's badge via the `X-MiniProfiler-Ids` response header. **OTel/mini-profiler conflict**: `opentelemetry-instrumentation-pg` prepends a wrapper that calls `super`; mini-profiler's pg patch then aliases the prepended method as `_without_profiling` and redefines `exec_params` — and OTel's `super` lands on the redef, which calls the alias, which is OTel's wrapper, infinite loop on the first query. Fixed by disabling OTel's PG auto-instrumentation in `RACK_ENV=development` only (`OpenTelemetry::Instrumentation::PG` → `{ enabled: false }` in [app/tracing.rb](app/tracing.rb)'s `use_all` config). Staging + production keep OTel pg spans untouched since mini-profiler isn't loaded there. **Backtrace noise**: by default mini-profiler attaches a full Ruby call stack to every recorded query — useful for slow queries, just noise for the dozen sub-10ms reads on a normal page render. Set `Rack::MiniProfiler.config.backtrace_threshold_ms = 250` so the stack only shows for queries over 250ms (genuinely slow joins, ranker scans, FTS searches); fast queries still get a row with duration but no stack. No production surface; no behavior change for signed-in users in test or prod.

## [x] 65. Webcomics & Humor

Seed a new "Webcomics & Humor" content area with curated free + publicly-available feeds. The app already supports everything technically (standard RSS / Atom via `FeedParser`); this was a curation + taxonomy task.

**Shipped.** New top-level topic `:humor` (label: "Humor") in `FeedCatalog::TOPICS`, with one category under it: `:webcomics` ("Webcomics & humor"). Added 8 catalog entries — all verified live + free + no API key, polling at `PERSONAL_BLOG_INTERVAL` (4h) since most update daily-ish at most: **xkcd** (Randall Munroe), **Saturday Morning Breakfast Cereal** (Zach Weinersmith), **The Oatmeal** (Matthew Inman), **Existential Comics** (philosophy panels), **Dinosaur Comics** (Ryan North's never-changing-art strip), **Poorly Drawn Lines** (Reza Farazmand), **Wondermark** (David Malki's vintage-clipart panels), and **Cyanide & Happiness** (Explosm.net stick-figure black comedy). New onboarding chip on `/welcome` (😂 "Humor") seeds the first 6 of those for any user who picks it; the other two are opt-in via `/feeds` catalog browse. Each URL was `curl`-verified for live 200 + valid XML before adding. Catalog grew from 100 → 108 entries.

Spec update: [spec/feeds_topic_spec.rb](spec/feeds_topic_spec.rb) — the `TOPICS.keys` exhaustive-match now includes `:humor` (the other assertions there are non-strict and didn't need changes). AGENTS.md catalog-count refs bumped 79 → 108 (which were stale before this work anyway).

**Reading-view polish for comics.** First pass had two visual problems: the `.article-hero` rule was `object-fit: cover` + `max-height: 260px`, which cropped the comic and made dialogue unreadable; and there was no way to expand the image for a closer look. Both fixed:

- **Comic-specific hero rule** ([public/style.css](public/style.css)): `.article-hero.is-comic` overrides `cover` → `contain`, drops the 260px cap (now `max-height: 80vh; height: auto`), and removes the placeholder background. The conditional class is set in [views/article.erb](views/article.erb) based on `@feed['topic'] == 'humor'`, so normal news/podcast/YouTube articles keep their existing tight hero. The catalog-add path already plumbs `topic: FeedCatalog.topic_for(entry).to_s` into `feeds.topic`, so any subscribed webcomic gets the comic rendering automatically.
- **Click-to-zoom lightbox** ([public/image-lightbox.js](public/image-lightbox.js) + style.css `#img-lightbox-overlay`): a small singleton overlay that wires onto every `.article-hero` and every `<img>` inside `.reading-view .article-body`. Click any of them → fullscreen overlay at `max-width: 95vw / max-height: 92vh`; click outside / hit Escape / click the × button to close. Idempotent across Turbo body swaps via a `data-lightbox-bound` per-element sentinel (same pattern as the [feedback_turbo_double_fire](.claude/) memory). `cursor: zoom-in` on the source image gives the affordance.

**Header refactor + dedicated /comics index.** Adding Comics to the existing flat nav would push it to 6 top-level links + 2 dropdowns + 2 icons — too busy. Refactored the per-content-type destinations under a single **Browse ▾** dropdown:

```
Tech Feed Reader │ Articles  ★ Bookmarks  Browse ▾  AI ▾  Manage ▾  Admin  🔍  🚌
                                          ├── Podcasts
                                          ├── YouTube
                                          ├── Sports
                                          └── Comics
```

Visible top-level links go from 6 to 3 while every content type stays one hover (or tap) away — the existing AI / Manage dropdowns already worked on `:hover` and `:focus-within`, so the new Browse ▾ reuses the same CSS. Active highlighting: Browse lights up for any of `/podcasts /youtube /sports /comics` (or their sub-paths) EXCEPT `/sports/manage`, which keeps lighting up Manage ▾ as before.

New `GET /comics` route ([app/main.rb](app/main.rb)) mirrors `/podcasts` and `/youtube`: subscribed-series tile grid keyed by feed (showing the latest panel image as the cover so the page looks alive even when every series shares its own logo), plus a "Recent panels" linear list. Backed by `ArticlesStore.comic_feeds(user_id)` — same shape as `podcast_feeds` / `youtube_channels`, filtered by `f.topic = 'humor'` since the catalog-add path plumbs the category's topic through. Empty state points at `/feeds` catalog so users know how to subscribe.

6 new examples in [spec/comics_route_spec.rb](spec/comics_route_spec.rb) cover the empty state, subscribed-series render, non-humor-exclusion, nav exposure, and the store helper's ordering + topic filter.

## [x] 66. Comics

On the comics page top area, Subscribed series, it says that the feed has say 10 panes. Clicking on the element takes the user to the latest panel. Clicking on the element should take the user to a page that shows the 10 panels. Then the user can click on an element in the list and go to than specific panel.

Also, in tbe "Recent panels" area, can you add the comic strip name to the element.

**Shipped.** Two changes on `/comics`:

- **Series tile target** — was jumping to `/article/:latest_uid` (the latest panel), which felt like a dead-end. Now opens a new `GET /comics/:feed_id` series archive listing the most recent 30 panels with thumbnails, titles, and dates; tiles in the archive click through to `/article/:uid` where the existing comic-hero rendering + image lightbox handle the actual viewing.
- **Recent panels meta line** — now surfaces the source series name (xkcd / SMBC / etc.) as a link back to `/comics/:feed_id`. `ArticlesStore.recent` doesn't JOIN feeds, so the route now also loads `@feeds_by_id` (same pattern as `/podcasts` and `/youtube`) and the view looks the title up.

New route guards (404 on): non-existent feed, feed the user isn't subscribed to, feed whose topic isn't `humor`. 6 new examples in [spec/comics_route_spec.rb](spec/comics_route_spec.rb) cover the panel list, empty state, all three 404 paths, and the series name appearing as a link on the index recent-panels rows.

## [x] 67. Rugby Page

On the /sports/league/fifa-world page, there's a link for each country. The link goes to an article not found page. Should that be the case? During the world cup will the pages have content?

The same is the same for /sports/league/mls.

Do a sweep of all the league pages. Perhaps we should remove the links. Or take the user to a page where they can subscribe to feeds for the team. Please analyzee and make a recommendation.

**Analysis.** The 404 isn't FIFA-specific or MLS-specific — it's universal. `/sports/team/:slug` was looking up via `SportsTeams.find` ([app/sports_teams.rb](app/sports_teams.rb)), a hand-curated Ruby module shipping only 5 teams (Eagles / Sixers / Union / All Blacks / Tennis). Every standings table on `/sports/league/:slug` links every team row to `/sports/team/<slug>`, so anything that wasn't one of those 5 — every FIFA-World country, every NFL team besides Eagles, every NBA team besides Sixers, every MLS team besides Union, every rugby/cricket/baseball team — 404'd. Not a per-league bug; the same root cause hit every league page.

**Why "DB fallback team page" beats "remove links" or "subscribe-only page".** Removing the links would deprive users of the structured data we already have (DB-side `sports_teams` + `sports_matches` + `sports_standings` are populated from ESPN sync). Pointing them at a feed-subscription page punts on the actual question — most users following Brazil during the World Cup care about the fixture / score / standing, not subscribing to a Portuguese-language Brazilian RSS feed. The shipped fix gives them both: a useful page with the structured data, AND an empty-state CTA toward `/feeds` when there's no article coverage.

**Shipped.** `GET /sports/team/:slug` now tries the curated Ruby module first, then falls back to `SportsTeamsStore.find_by_slug` for DB-side teams ([app/main.rb](app/main.rb)). A new lean template [views/sports_team_db.erb](views/sports_team_db.erb) renders:

- **Header** — team logo + name, league link (back to standings), follow/unfollow toggle
- **Standings position** — group / rank / record / streak / "Full standings →" if the row exists
- **Upcoming fixtures** — next 8 matches with opponent links (so navigating across teams works), kickoff time, venue, LIVE badge
- **Recent results** — last 6 finals with score
- **Mentions** — articles surfaced via `SportsEntityArticlesStore.refresh_for` (FTS5 phrase MATCH on the team name) when the user has any feed that mentions the team
- **Empty state** — graceful "no fixtures, results, or articles yet" copy that explains tournaments fill in via `make sync-sports` and nudges toward `/feeds` for article coverage

Curated teams (the 5 in `SportsTeams::TEAMS`) keep their rich existing page; the regression-guard spec asserts `/sports/team/eagles` still renders the Bleeding Green Nation blurb. 6 new examples in [spec/sports_team_db_route_spec.rb](spec/sports_team_db_route_spec.rb) cover both paths plus all four data-availability states. Full local suite: **1479 / 0**.

## [x] 68. Sports — followed teams not appearing on /sports

User followed three MLB teams (Phillies, Dodgers, Mets) but `/sports` only showed the four curated teams (Eagles / Sixers / Union / NZ Rugby). The "Major League Baseball" button was also missing from the "By League" area.

**Root cause(s)** — three interacting issues, all stemming from the curated Ruby module (`SportsTeams::TEAMS`, ~5 hardcoded teams) vs DB-side catalog (`sports_teams` table, populated from ESPN sync) split first identified in STUFF #67:

1. `/sports` route's `@teams_with_subs` was built only from the curated module, so DB-side followed teams (everything outside Eagles/Sixers/Union/All-Blacks/Tennis) had no panel.
2. `SportsSync::TEAM_SCHEDULE_SPORTS` lacked `baseball`, so MLB team schedules never synced — even after fix #1 lands, score tiles would stay empty until matches existed.
3. `SportsSync.ensure_team!` and the inline standings-sync logic always created a fresh `<league>-team-<external_id>` row when `find_by_external` missed — splitting every catalog-seeded MLB team into two rows (`phillies` natural + `mlb-team-22` ESPN), so the user's `phillies` follow pointed at an empty row while all the data lived under `mlb-team-22`.

**Shipped.**

- **Overview merge** ([app/main.rb](app/main.rb)): `/sports` now merges curated + DB-followed teams into a unified `@teams_with_subs`, deduplicated by slug. New `db_team_as_curated(row)` helper normalizes a sports_teams row to the symbol-keyed shape the view expects. Score tiles, the TOC team-button row, and "Last game" tile rendering all flow through unchanged.
- **Baseball schedule sync** ([app/sports_sync.rb](app/sports_sync.rb)): added `baseball` to `TEAM_SCHEDULE_SPORTS`. ESPN's `/apis/site/v2/sports/baseball/mlb/teams/<id>/schedule` endpoint returns full schedules; verified live for Phillies (external_id 22, ~2MB response).
- **Catalog promotion** ([app/sports_sync.rb](app/sports_sync.rb) + [app/sports_teams_store.rb](app/sports_teams_store.rb)): `ensure_team!` now falls back to a case-insensitive name lookup within the league before auto-creating. When the ESPN payload matches a pre-existing catalog row (`phillies` / `dodgers` / `mets`), that row gets promoted to ESPN-tracked (its `source_provider` + `external_id` rewritten) so future syncs find it via the steady-state `find_by_external` path. New `SportsTeamsStore.find_by_name_in_league`. Standings sync refactored to call `ensure_team!` so it gets the same behavior.
- **One-shot backfill** ([scripts/dedup_sports_teams.rb](scripts/dedup_sports_teams.rb)): collapses pre-existing duplicate rows (`<natural>` + `<league>-team-<external_id>` pairs sharing a league_id + name). Moves matches, standings (collision-safe via dedup), entity_articles (INSERT…ON CONFLICT pattern), and follows (idempotent: drops auto-slug follow if user already follows natural), then promotes the natural row to ESPN-tracked and deletes the auto row. Wrapped in a transaction per pair. Dry-run by default; `--apply` to commit. Already run against dev (3 MLB pairs collapsed).

11 new examples across [spec/sports_overview_db_teams_spec.rb](spec/sports_overview_db_teams_spec.rb) (4 — tile renders for DB-followed team with synced final, TOC button without final, orphan-follow no-crash, no-duplicate-when-both-sources-match) and [spec/sports_sync_catalog_promotion_spec.rb](spec/sports_sync_catalog_promotion_spec.rb) (7 — catalog promotion, auto-slug fallback, idempotence, case-insensitive name match, plus 3 store-level tests of `find_by_name_in_league`). Full local suite: **1490 / 0**.

## [x] 69. Sport Teams Follow

Ok. I think I see the pattern. When I follow on this page /sports/manage/basketball/nba, the team doesn't appear on the /sports page. However, when I follow from the league page, it works.

Can you investigate? Perhaps the manage page is doing something different. Could this lead to the duplication problem you discovered?

**Root cause.** Same family as STUFF #68, opposite direction. `/sports/manage/basketball/nba` reads its team list from `SportsCatalog` (Ruby module) where the slugs are human-readable (`lakers`, `celtics`, `bucks`). The follow form POSTs `slug=lakers`. The handler called `ensure_catalog_team_in_db('lakers')`, which called `SportsTeamsStore.upsert(slug: 'lakers', source_provider: 'espn', external_id: '13', ...)`. But `upsert` looks up by `(source_provider, external_id)` first — and the ESPN standings sync had already created an `nba-team-13` row for the Lakers under that same external_id. `upsert` updates name/image/etc. on the existing row but **leaves the slug as `nba-team-13`**. Meanwhile `sports_follows` got `value='lakers'`. Then `/sports`'s `SportsTeamsStore.find_by_slug('lakers')` returned nil and the Lakers never surfaced.

Every NBA/NFL/WNBA team in the dev DB was affected — only the 4 hand-seeded teams (Eagles / Sixers / Union / All Blacks) escaped because they were inserted with their natural slug at seed time.

**Shipped.**

- **Slug rename in `ensure_catalog_team_in_db`** ([app/main.rb](app/main.rb)) — detect the mismatch (DB row found via `find_by_external` whose slug differs from the catalog slug) and rename via the new `SportsTeamsStore.rename_slug!` before running `upsert`. Future follows from /sports/manage land on a row whose slug matches.
- **`SportsTeamsStore.rename_slug!(id, new_slug)`** ([app/sports_teams_store.rb](app/sports_teams_store.rb)) — small UPDATE-only path; `upsert` deliberately never touches slug for existing rows, so this is the dedicated promotion lever.
- **One-shot backfill** ([scripts/normalize_team_slugs_to_catalog.rb](scripts/normalize_team_slugs_to_catalog.rb)) — walks `SportsCatalog.all_teams`, finds DB rows whose slug differs from the catalog's, renames the row + rewrites any `sports_follows.value` entries to match (deduping per-user when both halves of the rename were followed). Dry-run by default; `--apply` to commit. Safe because matches/standings/entity_articles all FK by `team.id`. Already applied to dev — 39 renames (NFL + NBA + WNBA teams that previously lived under `<league>-team-<external_id>` auto-slugs).

5 new examples in [spec/sports_team_follow_slug_rename_spec.rb](spec/sports_team_follow_slug_rename_spec.rb) cover the store-level `rename_slug!`, the POST `/sports/teams/follow` slug-rename path (with auto-slug row pre-existing), idempotence (no-op when slug already matches), and the cold-start path (no DB row at all). Full local suite: **1495 / 0**.

## [x] 70. Sport Tournaments

In the /sports/manage/tennis area, can we add a list of the major tennis tournaments for all over the world. Grand Slams and others. The user should be able to subscribe to a tournament and recieve articles and relevant information. For example, the French Open is happening right now. I would love to be able to see:

- articles
- current ladder
- recent matches and scores

Also, coming soon to America is the World Cup Soccer Tournament. We should add the ability to subscribe to tournaments like this in every sport.

**Shipped (MVP — catalog + follow + surface; tennis bracket rendering deferred).**

**Key insight.** "Tournament" maps directly onto our existing `sports_leagues` table — FIFA World Cup already lives there as `slug='fifa-world'`. The `sports_follows` table already supports `kind='league'` (`KINDS = %w[team player league]`); it was just never wired into the UI. Reused existing infrastructure rather than building a parallel table.

**Catalog** ([app/sports_catalog.rb](app/sports_catalog.rb)) — added a `format:` field to league entries (`:season` default, `:tournament` for event-shaped). **60 tournament entries** across every sport in the catalog:

- **Tennis (19)** — 4 Grand Slams (Australian Open / Roland Garros / Wimbledon / US Open) + 9 ATP Masters 1000 (Indian Wells, Miami, Monte-Carlo, Madrid, Rome, Canada, Cincinnati, Shanghai, Paris) + 4 women's-only WTA 1000 (Dubai, Doha, Beijing, Wuhan) + ATP/WTA Finals.
- **Soccer (5)** — FIFA World Cup + Women's World Cup + UEFA Euro + Copa América + UEFA Champions League.
- **Rugby (2)** — Men's + Women's Rugby World Cup.
- **Cricket (8)** — ICC Cricket World Cup, Women's Cricket World Cup, Men's + Women's T20 World Cup, Champions Trophy, World Test Championship, The Ashes, Asia Cup.
- **Golf (12)** — 4 men's majors (Masters, PGA Championship, US Open, The Open) + The Players + Ryder Cup + Presidents Cup + 5 LPGA majors (Chevron, US Women's Open, KPMG Women's PGA, Evian, AIG Women's Open) + Solheim Cup.
- **Motorsport (7)** — Le Mans 24, Indy 500, Daytona 500, Monaco / British / Italian GP, Dakar Rally.
- **Horse Racing (7)** — US Triple Crown, UK Flat, UK Jumps, Dubai World Cup (the four existing event-series leagues marked `:tournament`) + Melbourne Cup, Japan Cup, Prix de l'Arc de Triomphe.

New helpers `SportsCatalog.tournaments_for(sport_slug)`, `.seasons_for(sport_slug)`, `.find_tournament(slug)`.

**Follow plumbing** ([app/main.rb](app/main.rb)) — `POST /sports/leagues/follow` + `/sports/leagues/unfollow` mirror the team-follow handlers. `ensure_catalog_league_in_db(slug)` lazy-upserts the catalog league into `sports_leagues` (same pattern as `ensure_catalog_team_in_db`).

**Manage UI** ([views/sports_manage_sport.erb](views/sports_manage_sport.erb)) — per-sport manage page now splits into **Leagues** (drill-down cards for ongoing seasons) and **📅 Tournaments** (inline ★ Follow toggle on each card). Followed tournaments get a green is-followed border.

**`/sports` overview** ([views/sports.erb](views/sports.erb)) — new "📅 Following tournaments" section above the TOC. One tile per followed league with sport emoji + tournament name + blurb. Click → `/sports/league/:slug` (existing route — shows standings for FIFA-shape tournaments; tennis Grand Slams show empty state for now since their event-shaped data doesn't fit a standings table).

**Sync wiring** ([app/sports_sync.rb](app/sports_sync.rb)) — `SportsSync.run!` now also calls a new `sync_followed_league_events!` which walks `sports_follows.kind='league'` and calls ESPN's `league_scoreboard` for each league with `source_provider='espn'`, upserting every event into `sports_matches`. Without this, following the FIFA World Cup as a tournament left the matches table empty unless the user also followed specific participating teams (since the existing `sync_team_schedules!` only iterates `kind='team'`). Verified live against ESPN: `make sync-sports` pulls 2 FIFA World Cup events on first run from the dev DB. Catalog-source tournaments (most tennis Slams, golf majors, horse-racing classics, cycling) are skipped gracefully — they'll sync when a provider lands for them. Also corrected `fifa-womens-world` to carry `source_provider: 'espn'` + `external_id: 'soccer/fifa.wwc'` so it picks up the new path. 4 new examples in [spec/sports_sync_followed_leagues_spec.rb](spec/sports_sync_followed_leagues_spec.rb).

**Out of scope (Phase 2 — separate STUFF item):** tennis bracket rendering on `/sports/league/:slug` (ESPN exposes draws via the scoreboard `groupings` block, which doesn't fit the current standings template); per-tournament dashboard with live scores during ongoing tournaments; article bridging via `SportsEntityArticlesStore.refresh_for(kind: 'league', ...)`.

**14 new examples** in [spec/sports_tournament_follow_spec.rb](spec/sports_tournament_follow_spec.rb) cover catalog helpers (tournaments/seasons split, cross-sport find), `POST /sports/leagues/follow` (happy path, idempotence, reuse-existing-row, 404, 400), unfollow, the manage view's Leagues/Tournaments split + followed-state button flip, and the `/sports` follow surface. Full local suite: **1509 / 0**.

## [x] 71. Sports Calendar

On the /sports/calendar page, each sports team appears to be a link; however, the link doesn't do anything. It should take the user to the sports team's page.

**Shipped.** Stale gate from before STUFF #67. The calendar view was rendering team chips as `<a>` only when `SportsTeams.find(slug)` returned a hit — i.e. only for the 5 curated Ruby-module teams (Eagles / Sixers / Union / All Blacks / Tennis). Everything else fell through to a `<span>` non-link with the comment "_/sports/team/:slug 404s for structured-only opponents_". That hasn't been true since STUFF #67 made the team detail route fall back to `SportsTeamsStore.find_by_slug`. Removed the `linkable` gate in [views/sports_calendar.erb](views/sports_calendar.erb) — every team chip is now a link. Updated [spec/sports_calendar_spec.rb](spec/sports_calendar_spec.rb)'s linkability assertion to match the new behaviour (was: "Cowboys → span"; now: "Cowboys → href"). Full local suite: 1511 / 0.

## [x] 72. Biking

Biking is a popular sport. Let's add as a category. Follow the same as other sports:

- subscribe to tournaments
- follow teams
- follow players

**Shipped.** Added cycling as a new `'cycling'` sport in [app/sports_catalog.rb](app/sports_catalog.rb) (slug `cycling` — the internationally-standard term, displayed as "Cycling 🚴"). Reuses every existing route + follow path; no new code beyond catalog data.

- **Two season leagues** — UCI WorldTour (Men) + UCI Women's WorldTour with **13 pro teams** total (UAE Team Emirates, Visma | Lease a Bike, INEOS Grenadiers, Soudal Quick-Step, Lidl-Trek, Red Bull–Bora–hansgrohe, Alpecin-Deceuninck, Movistar, SD Worx–ProTime, Visma Women, Lidl-Trek Women, Canyon//SRAM, Movistar Women).
- **5 Grand Tours** as tournament-format entries — Tour de France, Giro d'Italia, Vuelta a España, Tour de France Femmes, La Vuelta Femenina.
- **5 Monuments** — Milan–San Remo, Tour of Flanders, Paris-Roubaix, Liège–Bastogne–Liège, Il Lombardia.
- **UCI Road World Championships** (rainbow jersey).
- **Notable rider chips** on every team — Pogačar / Vingegaard / Evenepoel / van der Poel / Roglič / Mads Pedersen / Vollering / Kopecky / Vos / Niewiadoma / etc. Click any chip → `/sports/player/:slug` via the existing `catalog_player_slug` resolver and lazy upsert.

All three asks satisfied through existing infrastructure: tournament subscriptions via `POST /sports/leagues/follow` (STUFF #70); team follows via `POST /sports/teams/follow`; player follows via the chip-click flow used by tennis + NBA.
**Sync note.** Cycling catalog entries use `source_provider: 'catalog'` (no `external_id` mapping) because ESPN doesn't cover pro cycling. `make sync-sports` gracefully skips them — pro cycling teams + tournaments will populate via a UCI provider in a follow-up phase. Following them today still works for the article-bridging and UI-affordance dimensions; just no live match / standings data until the provider lands.

5 examples in [spec/sports_cycling_catalog_spec.rb](spec/sports_cycling_catalog_spec.rb) cover sport declaration, season slugs (exhaustive contain_exactly), Grand Tours + women's stage races, Monuments + Worlds, players-chip presence on every team. Full local suite: **1516 / 0**.

## [x] 73. Sources of Sports Data — Phase A

Given that ESPN is limited with information, we need to identify sources of information for our new Sports Tournament areas. For each tournament and sport, we need to find sources of information: news and scores. We need to do a comprehensive review of each tournament. "make sync-sports" should incorporate these new sources.

**Shipped (Phase A).** Two new providers + the Wikipedia summary surface on every league page. Phase B (`football-data.org` for non-ESPN soccer; PGA Tour leaderboards; Wikipedia infobox extraction for tournament results) deferred to a follow-up STUFF item.

**Source review.** Posted as in-thread analysis (verified candidates via `curl`):

- ✅ **Jolpica (Ergast successor)** — F1 races / drivers / constructors. No auth.
- ✅ **OpenF1** — F1 live timing alternative. No auth. (Not shipped this round; Jolpica covers Phase A.)
- ✅ **Wikipedia REST API** — summary endpoint covers every tournament in the catalog uniformly. No auth, generous free tier. WMF guidelines followed (User-Agent + 24h cache).
- ⚠️ **football-data.org** — works but needs registered key. Deferred.
- ❌ **ProCyclingStats / ESPNcricinfo** — return 403 to plain HTTP; would need browser fingerprinting. Deferred.
- ❌ **ESPN golf / cycling endpoints** — return 404. Not exposed publicly.
- 🚫 **Horse racing** — no good free source. Stays catalog-only.

**F1 via Jolpica** ([app/providers/jolpica_f1.rb](app/providers/jolpica_f1.rb)) — new provider hitting `api.jolpi.ca/ergast/f1/<year>.json` (the active community mirror; the original ergast.com retired April 2025). `season(year)` returns Array<Race> with circuit + country + scheduled_at + status (past races flagged `:final`, future ones `:scheduled`). `season_results(year)` adds podium winner per race. New `SportsSync.sync_f1!` is now part of `SportsSync.run!`; gated on `f1_followed?` (skip the fetch when no user follows `formula-1` as a league) so we don't pull 22 races for a dataset nobody cares about. Races land in `sports_matches` with both `home_team_id` and `away_team_id` NULL — F1 isn't team-vs-team; `period` carries "Round 7 — Monaco Grand Prix" and `venue` carries "Circuit de Monaco, Monaco". Confirmed live: `SportsSync.sync_f1!` pulls the **22-race 2026 F1 calendar** on first invocation; the existing Fixtures + Recent results sections on `/sports/league/formula-1` render them with no further view work. 5 examples in [spec/providers_jolpica_f1_spec.rb](spec/providers_jolpica_f1_spec.rb) cover the parse paths.

**Wikipedia summary** ([app/providers/wikipedia.rb](app/providers/wikipedia.rb) + [app/sports_leagues_store.rb](app/sports_leagues_store.rb) + migration `005_sports_leagues_wikipedia.sql`) — every league row now carries `wikipedia_title` (catalog metadata) + `wikipedia_summary` (cached JSON) + `wikipedia_summary_fetched_at` (TTL stamp). New `Providers::Wikipedia.summary(title)` hits `en.wikipedia.org/api/rest_v1/page/summary/{title}` with a proper User-Agent and 8s timeout per WMF guidelines. `refresh_for_league(league)` is the caller-friendly entry point — no-ops when the title isn't set (most catalog entries until I expand the map) and skips the network when the cache is fresh (TTL = 24h). Wired into the `/sports/league/:slug` route handler; renders an "About" section above Fixtures with thumbnail + extract + "Read on Wikipedia →" link. **46 catalog tournaments now have a Wikipedia title** declared in `SportsCatalog::WIKIPEDIA_TITLES` (every Grand Slam + Masters 1000 + every major soccer/rugby/cricket/golf tournament + every Monument + Grand Tour + every headline motorsport event). 8 examples in [spec/providers_wikipedia_spec.rb](spec/providers_wikipedia_spec.rb) cover summary fetch, blank-title no-op, 404 handling, percent-encoding, refresh-cache TTL behaviour. Verified live against `en.wikipedia.org/api/rest_v1/page/summary/Formula%20One` from a one-off call — returns the Formula One overview as expected.

Full local suite: **1539 / 0** (13 new examples across the two provider specs + cross-cutting test coverage that exercises the refreshed `/sports/league/:slug` route).

## [x] 74. Sports Data — Phase B (API-Sports paid tier)

Phase B of STUFF #73 — close the gaps Phase A left (NHL, golf leaderboards, cricket live scores, lower-tier soccer leagues, MMA) via a paid multi-sport data API.

**Provider:** [api-sports.io](https://api-sports.io) — $10/mo for 7,500 req/day across all their per-sport sub-APIs (football, basketball, baseball, hockey, F1, MMA, rugby). One auth key works across every sub-API. JSON, well-documented, generous free tier (100 req/day) for development.

### Operator step — sign up + provide the key

1. Go to https://dashboard.api-football.com/register and create an account (free; uses email + password).
2. Confirm the email; the dashboard issues an API key under **Account → My Access → API Key**.
3. (Optional but recommended) Upgrade to the **Pro** plan ($10/mo) for 7,500 daily requests. The free tier (100/day) is enough to develop + run the daily sync once.
4. Drop the key into `/Users/outten/src/tech-feed-reader/.env` on your laptop AND into `/opt/app/.env` on the Droplet:

   ```env
   API_SPORTS_KEY=<paste-the-key-here>
   ```

5. Restart the dev server (`make stop && make run`) to pick up the new env var; on the Droplet, `make deploy` will roll the value into the container.
6. Tell me the key is in place; I'll wire up the provider + sync paths. Don't paste the key into chat — the .env file is the source of truth and I'll only ever check `ENV['API_SPORTS_KEY']` from code, never log or echo it.

### What this unlocks (Phase B build scope)

- **`Providers::ApiSportsFootball`** — soccer fixtures/standings/lineups for leagues beyond what ESPN covers (Bundesliga 2, lower English divisions, Saudi Pro League, Eredivisie, etc.).
- **`Providers::ApiSportsBasketball`** — NCAA + EuroLeague + WNBA detail beyond ESPN's coverage.
- **`Providers::ApiSportsHockey`** — NHL + KHL (we currently have nothing for hockey).
- **`Providers::ApiSportsBaseball`** — NPB + KBO depth beyond what we get for MLB today.
- **`Providers::ApiSportsRugby`** — proper rugby fixtures (the ESPN integration is limited to standings).
- **`Providers::ApiSportsF1`** — alternate to Jolpica; cleaner data shape for driver+constructor standings.
- **One key, separate provider modules** — same auth header (`x-rapidapi-key` or `x-apisports-key` depending on host) wrapped in a shared `Providers::ApiSportsBase` for HTTP plumbing + retry + rate-limit awareness.
- **Sync wiring** — extend `SportsSync.run!` with per-sport sync paths gated on follows (same pattern as `sync_f1!` from Phase A).
- **No new schema** — re-uses sports_matches / sports_standings / sports_teams from existing schema. New `source_provider='api-sports'` value.

### Cost guard

API-Sports' rate limit is per-day across the account. The daily sync (`make sync-sports`) bundled across ~6 sports will burn maybe 200-500 requests per run if we're thoughtful about caching and only sync sports that have at least one follower. The $10/mo Pro plan gives us 15× headroom for ad-hoc page-load fetches if we add any. If usage spikes, the next tier is $25/mo for 75,000/day.

**Shipped.** Five sport providers wired into `SportsSync.run!` via `sync_api_sports!`. Season resolution tries `Date.today.year - 1` first, then `year - 2`, so the sync stays live even when the API lags a season (the provider returns an informational error for future seasons; the fallback picks up the most recent complete season automatically).

**What landed:**
- `Providers::ApiSportsHockey` — NHL (league 57) + KHL (league 31). Verified live: 1,503 NHL 2024-season games synced on first run.
- `Providers::ApiSportsRugby` — Six Nations (51), Super Rugby Pacific (71), United Rugby Championship (76), Rugby Championship (85). League IDs corrected from pre-key estimates; verified via live endpoint.
- `Providers::ApiSportsBaseball` — NPB (2), KBO (5). Both verified present in 2024 season.
- `Providers::ApiSportsBasketball` + `Providers::ApiSportsFootball` — providers present and gated; catalog entries for additional soccer leagues and WNBA can be added as follow-ups.
- `SportsCatalog` updated: Six Nations, Super Rugby Pacific, URC, NPB, KBO carry `source_provider: 'api-sports'` + `api_sports_league_id`.
- `SportsSync` requires `sports_catalog` (was missing, caused NameError on first run).
- Sync is follow-gated per league — zero API calls when no api-sports leagues are followed.
- `API_SPORTS_KEY` absent → returns 0 immediately (safe for environments without the key).

**Not covered (defer):** golf leaderboards (ESPN covers Masters/PGA via `football/golf`; no free-tier api-sports golf endpoint), MMA (niche), lower-tier soccer leagues (add catalog entries + api-sports football league IDs as needed).

## [x] 75. Hockey Sports

Hockey Sports management /sports/manage/hockey/nhl is not like the others. Why don't we see the leagues sports team. And allow us to see their standings and following.

**Shipped (two PRs bundled):**
- `GET /sports/manage/hockey/nhl` (and any api-sports league with `teams: []`): now loads teams from the DB via `SportsTeamsStore.for_league` and renders them with individual `+ Follow` buttons — same grid as ESPN-backed leagues. 32 NHL teams populate on first sync.
- League-level `+ Follow league` toggle added to the manage-league page for api-sports leagues (required to enable the daily sync).
- `@followed_league_slugs` now passed into the `/sports/manage/:sport/:league` route.

## [x] 76. Tennis / Roland Garros

Both `/sports/team/tennis` and `/sports/league/roland-garros` show no match data despite the French Open being live.

**Root cause:** Roland Garros had `source_provider: 'catalog'` — no live data provider. api-sports has no tennis API. ESPN *does* expose the tournament at `site.api.espn.com/apis/site/v2/sports/tennis/atp/scoreboard` with 633 matches per tournament (player names, set-by-set scores in `linescores`, human-readable summary in `notes[0].text`).

**Shipped:**
- `Providers::ESPN.tennis_scoreboard(tour:, tournament_name:)` — parses the tennis-specific ESPN format (groupings → competitions → athlete competitors). Returns `TennisMatch` structs.
- `Providers::ESPN.normalize_tennis_competition` — maps ESPN set scores, winner flag, and notes summary to our match shape.
- `SportsSync.sync_tennis_league_events!` — new sync path for tennis leagues; stores each player as a `sports_teams` row (slug: `roland-garros-guo-hanyu`, external_id: ESPN athlete ID) so the existing fixtures view renders match cards without schema changes.
- `SportsSync.ensure_tennis_player!` — upserts a player-as-team row per match.
- `sync_followed_league_events!` branches on `sport == 'tennis'` to call the new path.
- Catalog updated: `roland-garros`, `australian-open`, `wimbledon`, `us-open-tennis` → `source_provider: 'espn'`, `external_id: 'tennis/atp'`, `espn_tournament_name:` (filter string).
- `/sports/team/tennis` (curated team page): new "Live tournament data available" callout links to any followed tennis league that has synced matches.
- Verified live: 494 Roland Garros matches synced (433 final, 61 scheduled).

## [x] 77. Match Cards

Can you render the Results by Round more nicely for the user? With team or user logo? Like the "Last Game" area? And sort by most recent -- ie. most recent first.

**Shipped.** Tennis results-by-round section replaced with proper match cards:
- **Player avatar** — ESPN headshot (`a.espncdn.com/i/headshots/tennis/players/full/{id}.png`) auto-loaded from the stored ESPN athlete ID. Falls back to player initials (first letters of first + last name) in a circular avatar when the image 404s or fails to load.
- **Winner highlight** — winning player's name is bold; sets shown in green with a 🏆 trophy icon.
- **Sets score** — `home_score` / `away_score` are sets won (e.g. "2 – 0"), clear at a glance.
- **Court** — venue from ESPN match data (e.g. "Paris, France — Court Chatrier") shown beneath the two player rows.
- **Date** — compact "May 30" label in a left column.
- **Sort order** — rounds sorted Final → Semifinal → QF → R4 → R3 → R2 → R1 → Qualifying, newest first within each round. Final and Semifinal groups start expanded (`<details open>`); deeper rounds start collapsed.
- New `.tennis-match-card` CSS grid layout + `.tennis-match-avatar` / `.tennis-match-winner` / `.sports-round-summary` classes added to `public/style.css`.

## [x] 79. All-sports match cards

Extend the tennis match card improvements to all sports on /sports/league/:slug.

**Shipped.** Unified `match_card_html` helper in `app/main.rb` renders one `<li>` per match, adapting automatically by sport:
- **Tennis** — player headshots (ESPN CDN) + initials fallback, bold winner, green set count, per-set score detail, court/venue.
- **F1** — single race card with sport emoji + "Round N — Race Name" label + venue.
- **Team sports** (NHL, rugby, soccer, baseball, basketball) — horizontal `home [logo] name | score – score | name [logo] away` with team logo from `sports_teams.image_url` (sport emoji fallback), winner name bold.
- Round grouping (`@results_by_round`) now triggers for any sport with non-empty `period` — F1 is auto-grouped; season sports get a flat "Recent results" list.
- Year split (`@show_year_split`) now applies to all sports when both current-year and historical matches exist.
- Old `whats-on-match` list replaced by `sport-match-list` / `sport-match-card` CSS for both Upcoming and Recent sections. Suite: 1539 / 0.

## [x] 78. Current vs. Past

For example, Rolland Garros is showing last year's matches versus current which is going on now. It is OK for historical; however, we should show current if a league's tournament is current. It is ok if all of the data is not available (for exmaple, finals) if in progress. Let's add.

**Shipped + extended to all sports (bundled with the "all sports" card pass).** The league route now splits tennis results into current-year and historical buckets before passing them to the view:
- `@finals_this_year` — matches whose `scheduled_at` starts with the current year (2026). These are the ongoing tournament's completed rounds.
- `@finals_historical` — all prior-year matches (Roland Garros 2025, etc.).

The view renders them in two separate `<details>` blocks:
- **2026 Results** — open by default. Rounds sorted Final → Semifinal → QF → deeper rounds; Final + Semifinal start expanded, the rest collapsed.
- **Previous year's results** — collapsed by default. Same round grouping inside.

Both sections use the same `tennis-match-card` layout (avatars, set scores, court). This way the current tournament is prominent and historical data is available but unobtrusive.

## [x] 79. Simple Games

Are there simple interactive, games we can add to the site that users can subscribe to? Some that I think of:

- checkers
- chess
- sudoku
- ro sham bo
- perhaps a daily logic puzzle

**Shipped (Daily Sudoku — Phase 1).** New `/games/sudoku` page with a fully playable daily puzzle. One puzzle per day generated server-side and shared across all users; progress autosaves per-user.

**What landed:**
- `SudokuGenerator` (`app/games/sudoku_generator.rb`) — backtracking generator with uniqueness verification. Three difficulties (easy/medium/hard); medium removes ~46 cells. Every generated puzzle is confirmed to have exactly one solution before being stored.
- `SudokuStore` (`app/games/sudoku_store.rb`) — puzzle CRUD + per-user state upsert (board string, JSON pencil-mark notes, elapsed seconds, completed_at). `ensure_today!` lazy-generates on the first request; `ensure_upcoming!(days:)` pre-generates a window.
- Migration `006_sudoku.sql` — `sudoku_puzzles` (date-keyed, one row per day) + `sudoku_states` (user × puzzle with UNIQUE constraint, idempotent upsert that never overwrites a completed_at once set).
- Routes: `GET /games` (redirects → `/games/sudoku`), `GET /games/sudoku` (renders today's board), `POST /games/sudoku/:id/state` (AJAX save, returns `{ok: true}`).
- `public/sudoku.js` — pure vanilla JS: 9×9 grid rendering, cell selection with row/col/box highlighting and same-digit highlighting, keyboard input (digits + arrow navigation), pencil-note mode (toggle with N or the Notes button), Check/Reset controls, live timer, AJAX autosave every ~3s and on solve, completion detection + celebration message.
- CSS in `public/style.css` — dark-mode aware, responsive (collapses to single column under 700px), Apple-style pill numpad buttons, green completion flash.
- **Games** added to the Browse ▾ dropdown (🎮 Games link to `/games`).
- `GenerateSudokuWorker` + daily `01:00 UTC` sidekiq-cron entry — pre-generates next 7 days so `/games/sudoku` always has a puzzle without blocking the request.
- `make generate-sudoku` + `scripts/generate_sudoku.rb` for on-demand pre-generation.
- Leaderboard strip on the sidebar shows today's completions ranked by solve time.
- `format_elapsed` helper (h:mm:ss / m:ss) shared between the sidebar leaderboard and the JS timer display.
- **14 specs** in `spec/sudoku_spec.rb` — generator shape (length, digit range, clue⊆solution, blank count, uniqueness), store CRUD (create, idempotence, state save, completed_at preservation), route 200/302, data-attribute embedding, AJAX save, `/games` redirect. Suite: **1553 / 0**.

**Deferred (Phase 2 — news trivia quiz):** see below.

## [x] 79 (Phase 2). News Trivia Quiz

Daily 5-question multiple-choice quiz generated by Claude from the last 24 hours of articles. One shared quiz per day; per-user answer tracking.

**What landed:**
- `TriviaGenerator` (`app/games/trivia_generator.rb`) — calls `claude-haiku-4-5-20251001` with today's 20 most recent articles as context. Prompt asks for exactly 5 JSON objects (question, a/b/c/d choices, correct letter, explanation, source title + URL). Strips markdown fences before parsing; filters out malformed entries; normalises correct letter to lowercase.
- `TriviaStore` (`app/games/trivia_store.rb`) — quiz CRUD, per-question answer upsert (`ON CONFLICT DO NOTHING` — first answer wins), score aggregation, leaderboard query. `ensure_today!` lazy-generates on first request.
- Migration `007_trivia.sql` — `trivia_quizzes` (date-keyed), `trivia_questions` (5 per quiz with choice columns + correct letter + explanation), `trivia_answers` (user × question UNIQUE, correct boolean).
- Routes: `GET /games/trivia` (renders today's quiz or unavailable state), `POST /games/trivia/:question_id/answer` (AJAX, returns `{correct, correct_letter, explanation}`).
- `GET /games` replaced the old sudoku redirect with a proper **games index** (`views/games.erb`) — two tiles (Sudoku + Trivia) each showing today's progress badge.
- `public/trivia.js` — progressive reveal: click a choice → disable all → AJAX submit → highlight correct (green) / wrong (red) → show explanation inline → update score badge → auto-show completion banner when all 5 answered.
- CSS — answer-choice pill buttons with hover/active states, correct/wrong colour highlights, explanation panel, leaderboard sidebar, games-index tile grid. Full dark mode.
- `GenerateTriviaWorker` + daily `01:30 UTC` sidekiq-cron entry. `make generate-trivia` + `scripts/generate_trivia.rb` for manual runs.
- **20 specs** in `spec/trivia_spec.rb` — generator (unavailable, empty, JSON parse, code-fence strip, key filtering, letter normalisation), store (lookup, question fetch, answer submission, idempotence, score count, answers hash), routes (unavailable state, quiz render, score badge, AJAX answer, invalid letter 400), games index. Suite: **1573 / 0**.

## [x] 80. Bugs in Games

I found the following bugs in the current games:

## Sudoku

### Logic Errors Only

When inputting a a number in the cell, the app shows RED is bad and white if good. This allows the user to trial and error their way to a succesful solution. We shouldn't do this to focus the user on using their abilities to solve the puzzle.

You should only error and not let a number to be entered if it breaks a rule of the game.

### Empty Sudoku Box

If I change pages and then come back to the daily sudoku page, the box that holds the puzzel is empty. It's not every time, but most of the time.

## New Trivia

### Right/Wrong Count

When answer questions, the count of right answers versus number of questions is always wrong. I always see 5/5 after I answer the last question when I see wrong answers while answering. If I refresh the page, the redisplayed right/wrong is correct.

Can you cbeck?

**Shipped.** Three fixes in [public/sudoku.js](public/sudoku.js) and [public/trivia.js](public/trivia.js):

1. **Sudoku — rule-only validation.** `renderCell` was comparing the entered digit against `solution[idx]` and flagging non-solution values red, letting users trial-and-error. Replaced with `conflictsWithRules(cells, idx, digit)` which checks only Sudoku constraints (duplicate in same row, column, or 3×3 box). Correct-but-not-matching-solution entries are now shown without any error colour; wrong-rule entries still go red. The explicit "Check" button still validates against the solution.

2. **Sudoku — empty board on Turbo navigation return.** Turbo snapshots the page before navigating away. The snapshot included `data-sudoku-wired='1'` on the board element, so on cache restoration `init()` returned early and the board appeared empty (cells rendered but JS listeners gone). Added a `turbo:before-cache` handler that clears `innerHTML` and the sentinel before the snapshot so restoration triggers a clean `init()`. `timerHandle` hoisted to IIFE scope so the handler can also clear the interval.

3. **Trivia — score badge always showing 5/5.** `updateScore()` and `showComplete()` counted `.trivia-choice-correct` elements — but every answered question adds one green button (the correct answer), so the count was always equal to the number of answered questions. Fixed by adding `.trivia-user-correct` to the card in `revealResult` when `data.correct` is true, then counting `.trivia-card.trivia-user-correct` for the score (only cards where the user's chosen answer was right). Suite: **1573 / 0**.

## [x] 81. Internet, Commercial Free Radio

Let's add a new content section: Internet, Commercial Free Radio.

I personally like https://somafm.com/ and would like to have them and their channels represented in the application. And allow the user to subscribe. Outside of the channels, there will be nothing to download as these feeds are MP3, AAC, etc. streams that are live.

In addition, I would like to recommend KCRW, Santa Monica, CA music channels and shows: https://www.kcrw.com/music

Also, suggest other popular Internet streams that technologies like.

Create a branch for this. Follow our process of manual checks and manual approvals for PRs and deployment.

**Shipped.** New dedicated `/radio` section — browse and manage commercial-free internet radio from one place.

- **`radio_stations`** + **`radio_follows`** tables (migration `008_radio.sql`). `radio_stations` is seeded from the catalog; `radio_follows` is per-user.
- **`RadioCatalog`** (`app/radio_catalog.rb`) — 16 curated stations in 3 groups: **SomaFM** (10 channels: Groove Salad, Drone Zone, Secret Agent, DEF CON Radio, Space Station Soma, Indie Pop Rocks, Underground 80s, Lush, Fluid, Cliqhop IDM), **Public Radio** (KCRW, KEXP, WFMU), **Independent** (Radio Paradise Main Mix, Radio Paradise Mellow Mix, NTS Radio 1). All stream URLs verified live.
- **`RadioStore`** (`app/radio_store.rb`) — `seed_catalog!`, `followed_stations`, `follow!`, `unfollow!`, `following?`, `stations_by_group`.
- **`/radio`** page — two sections: **My Stations** (subscribed, with ▶ Play + ✓ Following/+ Follow per card) and **Browse Catalog** (all stations grouped by provider with art, genre chip, description, and play/follow actions). Empty state guides new users to the catalog.
- **Global player live-stream mode** — when a radio station is loaded (`live: true`), the player hides the scrubber, skip-back, skip-fwd, and playback-rate controls; shows "● LIVE" in red instead of elapsed time. CSS scoped to `#global-player.is-live-stream`. Resume-position logic skipped for live streams.
- **`public/radio.js`** — loaded from `layout.erb`; wires play buttons (calls `window.Player.load({…, live: true})`) and follow/unfollow toggle (AJAX POST, updates button text in-place). Currently-playing card gets a blue border accent.
- **Browse ▾ nav** — 📻 Radio added alongside Podcasts / YouTube / Sports / Comics / Games.
- **`make seed-radio`** + `scripts/seed_radio.rb` for initial catalog seeding on deploy.
- **19 specs** in `spec/radio_spec.rb` — catalog structure (size, fields, URL uniqueness, groups), store (seed idempotence, follow/unfollow/following?/followed_stations), routes (page render, empty state, follow/unfollow JSON, 404 on bad station, nav link). Suite: **1592 / 0**.

## [x] 82. Correct Answer in News Trivia

It appears that the correct answer fo the news trivia quizz is generally the same:

- in production, choice A is correct across all five questions
- in development, choice B is four out of five, the remaining being C

Can you check and shuffle the deck better?

**Shipped.** Root cause: Claude consistently places the correct answer in early positions (typically 'a' or 'b') — a well-known LLM bias in multiple-choice generation. The generator was storing Claude's ordering verbatim. Fix: added `shuffle_choices` in [app/games/trivia_generator.rb](app/games/trivia_generator.rb) that extracts the four answer texts, shuffles them randomly, remaps to letters a–d, then records whichever letter now contains the originally-correct text. Applied in `parse_questions` before any question is returned. The correct answer text is always preserved; only its position changes. Suite: **1592 / 0**.

## [x] 83. Test Coverage

Let's add /admin/covera

**Shipped.** New `/admin/coverage` page backed by SimpleCov. Added `simplecov` gem to the test group; configured in `spec_helper.rb` (with branch coverage enabled and group filters for stores, routes, providers, workers, games, radio). After any `make test` run, `/admin/coverage` shows overall line % and branch %, a colour-coded progress bar, and a per-file table sorted by lowest coverage first. The full SimpleCov HTML report is served at `/admin/coverage/report` (auth-gated, not publicly accessible). Current numbers: **85% line / 67% branch**. `coverage/` added to `.gitignore`.

## [x] 84. Agents Update

Can you update the AGENTS.md file with the deployment process:

- manually changes need to be approved by me before making a PR
- PR creation needs to be approved by me
- only I can do PR merges after the GitHub actions run
- deployment to production needs to be deployed by me

**Shipped.** `AGENTS.md` Standard flow section rewritten to make all four gates unambiguous: (1) commit requires explicit approval + browser verify for UI; (2) PR creation requires explicit approval; (3) only the user merges PRs — no `gh pr merge` without direct instruction; (4) only the user deploys — no `make deploy-*` without direct instruction. Added a summary table of the four gates for quick reference.

## [x] 85. Finance / Markets + New Content Categories + Stock Ticker

Add four new content topics (Finance & Markets, World News, Science, Gaming) with ~30 curated RSS feeds. Plus a stock symbol feature: users can search for symbols (via Finnhub API), view a detail page with price/change/market cap, and follow symbols. Followed symbols display in a scrolling ticker bar on the dashboard. Background sync refreshes quotes every 15 minutes via Sidekiq cron.

New topics: `finance`, `world_news`, `science`, `gaming`.
New categories: `markets_news`, `world`, `science_pub`, `space`, `gaming_pub`.
New tables: `stock_follows`, `stock_quotes`.
New routes: `GET /stocks`, `GET /stocks/:symbol`, `POST /stocks/follow`, `POST /stocks/unfollow`.
New files: `app/stock_follows_store.rb`, `app/stock_quotes_store.rb`, `app/stock_quote_provider.rb`, `app/workers/stock_quote_fetch_worker.rb`, `app/workers/stock_sync_worker.rb`, `views/stocks.erb`, `views/stock_detail.erb`, `views/_stock_ticker.erb`, `public/stock-follow.js`.
Environment: `FINNHUB_API_KEY` required in `.env` / `.credentials` for stock features; app degrades gracefully without it.

**Status: merged** — PR #182 (index sync + ETF symbols + landing page), commit `774915e`. Also: `IndexSyncWorker` added for hourly major-index refresh; Finnhub free-tier `^` symbols swapped to ETF proxies (SPY/DIA/QQQ/etc.); `FINNHUB_API_KEY` wired into `docker-compose.yml` for production; visitor landing page updated with Stocks and Games feature cards.

## [x] 86. Force-run buttons on /admin/status

Added "Force run" button for `index_sync` on `/admin/status` (same pattern as sudoku/trivia regenerate). Route: `POST /admin/stocks/index-sync`.

**Status: merged** — shipped as part of PR #182.

## [x] 87. Beauty Pass

Let's do a beauty pass and fix minor issues in UI/UX. Items are:

- on the podcasts page, let's put "Recent episodes" above "Subscribed shows"
- on the comics page, let's put "Recent panels" above "Subscribed series"
- on the radio page, let's put "My Stations" above "Recommended for you"
- on the stocks page, in the "Major indices" area:
  - can you put each index in a panel element like the other pages
  - can you put a chart of the ups and downs of the day like you did for the Weather Application
- in the AI menu, can you put Triage firstGH

**Shipped on PR #183.** Five UX polish items across four pages:
- **Podcasts / Comics / Radio** — section order flipped: "Recent episodes" now leads `/podcasts`; "Recent panels" leads `/comics`; "My Stations" leads `/radio`.
- **Stocks major-indices sparklines** — each index card now renders an intraday price chart via `GET /api/stocks/sparklines` (Yahoo Finance free API, ~78 data points). Canvas-drawn green/red line with gradient fill + a day-range bar (low → high with current-price marker). New `StockQuoteProvider.sparkline` / `sparklines_for_indices`; drawing logic in [`public/stock-sparklines.js`](public/stock-sparklines.js).
- **AI nav dropdown reordered** — Triage first, then Topics, then Digests.

A follow-up PR (#184) fixed a nav-dropdown hover gap (CSS `::before` invisible bridge covers the 4 px gap between trigger and menu so hover doesn't break mid-cursor-move) and added click-to-toggle (`.open` class pinned on click; closed on outside click / Escape / menu-item selection via [`public/nav-dropdown.js`](public/nav-dropdown.js)).
## [x] 88. Food & Cooking

Add a new "Food & Cooking" content category with curated feeds covering recipe blogs, food journalism, and food podcasts. Should show up in the `/feeds` catalog, the `/welcome` onboarding chip picker, and `?topic=food` filtering on `/articles`.

**Shipped.** PR #185. Added `food` topic with three sub-categories — `food_recipes` (Serious Eats, Smitten Kitchen, Epicurious, 101 Cookbooks), `food_news` (Eater, Bon Appétit, NPR/The Salt, Civil Eats, David Lebovitz), `food_podcasts` (Gastropod, The Sporkful) — totalling 11 new catalog entries (138 → 149). Wired into onboarding with a 🍳 chip and starter URLs. Also shipped as part of this PR: a jump-nav TOC at the top of `/feeds` that groups all catalog categories by topic with anchor links to each heading.

## [x] 89. NPR and PBS

I feel like we have limited representation of NPR and PBS, which has some extremely broad content categories with amazing content that users love. Let's manage them under their own areas, as well as have categories under Browse. Allow the user to subscribe and unsubscribe to podcasts, news articles, and video shows. Video shows should play in an embedded player on our side or allow the user to view on PBS' site.

**Shipped.** PR #186, v0.23.0. Added dedicated `/npr` and `/pbs` browse pages, each with a "Recent" section (scoped to that topic), a "My NPR/PBS" section showing current subscriptions with AJAX unsubscribe, and a "Browse" catalog section with AJAX subscribe — all staying on-page via `source-page.js`. Added 22 new catalog entries: `npr_news` (5 feeds — NPR News, Politics, World, National, Science), `npr_podcasts` (9 — Fresh Air, Planet Money, Hidden Brain, How I Built This, Wait Wait, Code Switch, Short Wave, Tiny Desk, NPR Politics), `pbs_news` (5 — NewsHour headlines/politics/world/science/health), `pbs_shows` (4 — NOVA, Frontline, NOVA Presents, American Experience). Both topics wired into onboarding with 📻/🎬 chips. Catalog total: 149 → 171 (net +22 after dedup of one NPR News URL previously in `:world`).

## [x] 90. Radio Page Icons

Another beauty pass. A bunch of the radio page elements have broken links for the elements image. I'm seeing 404 errors as the links are relative, which our site doesn't help. Similar to other pages, can you check and fix those links. And be sure to add the ability to scan and fix already existing radio content to check and fix the links.

**Shipped.** Updated 13 broken `image_url` entries in `app/radio_catalog.rb`. Replaced 404/410 URLs for KEXP, WFMU, NTS Radio (×2), TSF Jazz, FIP family (×6), France Musique, Radio Swiss Jazz/Classic/Pop (×3), The Current, WXPN, WNYC, and Triple J with verified working URLs sourced from each station's `og:image` or logo assets. KCRW's URL returned 429 (WAF rate-limiting for bots) and was kept — it loads correctly in browsers. DB rows self-heal on next `/radio` visit since `RadioStore.seed_catalog!` runs on every request with `ON CONFLICT DO UPDATE`. Note: Radio Swiss URLs use Nuxt build-artifact paths and may need refreshing if their site redeploys with a changed logo.

## [x] 91. Content categories expansion — Health, Arts, History + UX

High-impact items from content analysis:

- **Fix /feeds filter bar**: subscribed-feeds chips are now dynamic — only show topics the user actually has feeds in (no phantom categories). Catalog chips show all topics so users can discover new content.
- **History topic**: `:mythos` category (previously under `:technology`) reclassified to `:history` with proper sub-categories `history_pub` / `history_podcast`. Smithsonian added. Existing Aeon, Daily Stoic, Myths & Legends, Stuff You Missed entries migrated.
- **Health & Wellness** topic: STAT News, Vox Health, NPR Health, WHO News, ZOE Science & Nutrition, Axios Health. Onboarding chip (🩺).
- **Arts & Culture** topic: Variety, NYT Movies, Guardian Film (film); Rolling Stone, Guardian Music, NPR Music, All Songs Considered (music); Literary Hub, Book Riot, NYT Books, Guardian Books (books). Onboarding chip (🎭).
- Catalog grows from 171 → 190 entries across 14 topics.

**Status: merged** — PR #189, v0.23.3. Also covers #92 (Environment, Business) and #93 (Travel, Mastodon, Politics) — all shipped through v0.23.5.

## [x] 94. Scroll position preservation — AJAX for remaining full-reload actions

Several button actions still do a full page POST + redirect, which reloads the page and drops the user back at the top. On long pages (/articles, /feeds, /stocks) this requires significant scrolling to get back to where you were.

Actions to convert to AJAX (in-place DOM update, no scroll loss):

- **👍/👎 thumbs on `/articles` list** — highest priority, longest page. Route already returns JSON when `Accept: application/json` is set; just needs a JS handler.
- **Sports manage page** — league follow/unfollow on `/sports/manage/:sport` reloads
- **Mutes add/delete** on `/feeds` — currently full reload
- **Tags add/delete** on `/feeds` — currently full reload

Already AJAX (no action needed): feeds catalog add/remove/weight, sports follow/unfollow, stock follow/unfollow, NPR/PBS subscribe/unsubscribe.

**Status: done.** Verified all four end-to-end (headless click, no full reload): articles-list 👍/👎 (`article-feedback.js`), mutes add/delete (`mutes-tags.js`, confirmed row added in place), tags add/delete (`/tags`, same handler), sports-manage league follow (`sports-follow.js`).

The sports-manage league follow was only *partly* wired by the earlier pass — adding the `js-sports-follow-form` class wasn't enough. Two bugs found + fixed: (1) `applyState` in `sports-follow.js` rewrote the form action to `/sports/teams/` for any non-player kind, so a league form's action became `/sports/teams/unfollow` after the first toggle (broke the 2nd click); now handles `kind === 'league'` → `/sports/leagues/`. (2) The sport-level league button (`sports_manage_sport.erb`) lacked `data-follow-label`/`data-following-label`, so its text never flipped; added them. Toggle now flips label + keeps the correct action on repeat clicks.

Original implementation notes: mutes/tags routes return JSON for `Accept: application/json`; `public/mutes-tags.js` handles AJAX add/delete for both with in-place DOM updates.

## [x] 95. Welcome-page feature cards for Stocks & Daily Games

The anonymous home page feature cards for "Stocks & indices" and "Daily games" rendered as plain text while the eight cards above them all carried a screenshot — breaking the alternating image/text rhythm.

**Status: merged** — PR #194, shipped in v0.24.0. Both cards promoted to `home-feature-with-image` in `views/home.erb` (no CSS change — `:nth-child(odd)` handles left/right placement); added two 1280×900 light-mode screenshots (`public/img/home/stocks.png`, `games.png`).

## [x] 96. Per-symbol stock news on /stocks/:symbol + in Articles/home

The `/stocks/:symbol` page was sparse (quote + stat cards only). Show recent news for the symbol, and when a user follows a symbol, route its news into the Articles section and the home page.

**Status: merged** — PR #195, v0.24.0. Yahoo Finance publishes a standard per-symbol RSS feed (no key, works for ETF index tickers too). `StockNewsFeed` (app/stock_news_feed.rb) maps a symbol to one feed in the existing catalog (topic `finance`), so its headlines flow through the ordinary feed→article pipeline. Following a symbol subscribes the user (news surfaces in `/articles?topic=finance` + home "To read today"); a "Recent news" section renders on the detail page. `scripts/backfill_stock_news_feeds.rb` reconciles follows created before the feature. No new table.

## [x] 97. Stock news cold-start fill + global ticker on every page

Two follow-ups: (a) a never-before-viewed symbol showed a static "Fetching…" placeholder until reload; (b) the followed-symbols ticker only appeared on the admin dashboard, not site-wide.

**Status: merged** — PR #196, v0.25.0. (a) The detail-page news section is now a partial (`views/_stock_news.erb`) that carries `data-stock-news-pending` when cold; `GET /stocks/:symbol/news` re-renders just that section and `public/stock-news.js` polls it, swapping in headlines the moment the background refresh imports them — no reload. (b) The scrolling ticker (followed symbols + major indices, via the `ticker_quotes` helper) now renders in `layout.erb` on every signed-in page; the dashboard-only inline render was removed.

## [x] 98. Rack Mini Profiler

Can you add rack-mini-profiler to the Development group. I'd like to profile some of the pages, particularly loading an article as it take a long time: 10,000 ms.

After installing, can you analyze why. Using the debugger it looks like the calls from turbo are serial and not parallel. Please investigate.

**Status: done (PR pending).** rack-mini-profiler was already in the `:development` group (added in #64, with stackprof for `?pp=flamegraph`). Investigation found the article load is **not** slow server-side: the document renders in ~130 ms warm (pure DB reads, no network/LLM in the route) and all 14 layout assets serve in ~7 ms total, fully parallel. The "serial, not parallel" effect is real but small — 10 concurrent dynamic requests ran ~2× faster than serial (not ~5× on 5 Puma threads), i.e. Ruby's GVL serializing the CPU-bound ERB/recommendation work in the single dev process; Turbo 8 also prefetches links on hover, firing request bursts that queue. Couldn't reproduce 10,000 ms locally (test article was text-only; a page with many slow external images would explain it). Shipped: **self-hosted Turbo** (`public/turbo.js`) instead of the render-blocking `unpkg.com` CDN (~200 ms off first paint, removes an external dependency). On the badge: it renders on every **full page load** (Cmd-R any page to profile it); Turbo Drive body-swaps suppress it, and the gem's Turbo integration has a flash-then-vanish race (unfixed through 4.0.1), so we deliberately left `enable_hotwire_turbo_drive_support` off. See #101.

## [x] 99. AJAX Thumbs Up and Down

On an article page, for example /article/19d3f8ceb73c, the thumbs up / down does a page reload. Can you convert this to AJAX.

**Status: done (PR pending).** The two feedback forms on the detail page already posted to `/article/:uid/feedback`, which *already* returned `{ok, value}` for `Accept: application/json` — so this was purely client-side. Extended `public/article-feedback.js` (which already AJAX-ifies the `/articles` + `/bookmarks` list rows) to also intercept the detail-page forms (`.js-article-feedback`, `data-feedback="up"|"down"`): on submit it fetches and re-renders BOTH buttons from the JSON `value` (each button's toggle target depends on the current state) with no reload, falling back to a normal submit on error. Moved the script's load from `views/articles.erb` into `views/layout.erb` so it serves both surfaces from one place (per the "JS in layout, not views" rule). Verified via a headless click: no full reload, 👍→"👍 Boosted" + `feedback-on-up`, hidden value flips, 👎 stays plain, second click clears.

## [x] 100. Puma cluster mode vs. threaded

Can you investigate if we should run Puma in cluster mode vs. threaded as we prepare for launch in production?

**Status: investigated — recommendation: stay threaded for launch.**

Current: one Puma process, threaded (`max_threads` 5), booted via `ruby app/main.rb`. Sidekiq is a separate process.

The case *for* cluster mode: Ruby's GVL lets only one thread run Ruby at a time, so threaded-only Puma can't use the Droplet's **4 vCPUs** (`s-4vcpu-8gb`) for the CPU-bound parts of a request (ERB rendering, the For-You ranker) — measured earlier (#98) as ~2× speedup on 10 concurrent requests, not ~5×. Forked workers each get their own GVL → true multi-core parallelism.

The case *against*, two blockers:
1. **Connection cap.** The managed Postgres is `db-s-1vcpu-1gb` (~22 usable connections). Budget = `workers × (threads + 1 ambient) + sidekiq ~6`. That caps the web at **~2 workers** (2×6 + 6 = 18 ✓; 4 workers = 30 ✗). Going past 2 workers needs a PG tier bump (`db-s-1vcpu-2gb` ≈ 47 conn) — a real cost decision.
2. **Fork-safety, unverified.** Prototyped a cluster config (`config/puma.rb` with `preload_app!` + `before_fork`/`before_worker_boot { Database.reset! }` + `config.ru`). Single-process boot worked; but in cluster mode the worker **segfaults on the first request inside the `pg` gem** (`pg/connection.rb:944` ← `pg_adapter.rb:147`). The environment is `pg-arm64-darwin` — i.e. **macOS, where `fork()` + libpq is a known crash class**; production is Linux and may well be fine, but it can't be validated on a dev Mac.

Recommendation: **keep threaded for launch.** The PG cap limits the upside to 2 workers, fork-safety is unverified, and the felt-latency wins already shipped (Phases 1–3: scoped `unread_count`, ranker cache, connection pool). Revisit cluster mode post-launch *only if* production profiling shows CPU saturation — and then validate the fork path on a Linux staging box and bump the PG tier first. The prototype was reverted to avoid shipping an unverified, footgun config; its design is captured here.

## [x] 101. Profiler -- moot -- won't do

Ok, so rack-mini-profiler won't work. Is there any similar service / Gem we could use that would work to profile our application. And in particular monitor the database performance.

## [x] 102. PBS Shows

Can you expand the list of PBS shows? For example, I don't see: Nature, the Ken Burns documentaries, Great Performances, American Experience, Washington Week, Finding Your Roots, The Great American Recipe, any food / cooking shows, etc. PBS has a lot of very popular shows, some of which you need to have an active membership to view, which is fine. We want to help promote PBS and NPR.

Please provide a more comprehensive list.

**Status: done (PR pending).** Expanded `pbs_shows` from 4 → 22 (catalog 258 → 276). PBS gates full episodes behind membership, so the new entries are each show's official YouTube channel (clips, previews, full episodes where posted) — every `channel_id` title-verified against the live feed. Added: Nature on PBS, PBS Terra, PBS Space Time, PBS Documentaries, Great Performances, Washington Week, American Masters, Antiques Roadshow, Masterpiece, Independent Lens, Secrets of the Dead, Ken Burns, Austin City Limits, plus PBS cooking shows America's Test Kitchen, Lidia's Kitchen, Christopher Kimball's Milk Street, Pati's Mexican Table, Cook's Country. Couldn't find a stable per-show feed for **Finding Your Roots** or **The Great American Recipe** (no dedicated channel/RSS — PBS publishes them only as playlists on its general channel); **PBS Eons**'s real channel couldn't be reliably resolved (YouTube handle resolution returned a wrong fallback), so it was dropped rather than risk a wrong feed.
