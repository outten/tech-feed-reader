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

## [ ] 38. Drop SQLite3

Now that we are on PostgreSQL, let's drop SQLite3 testing.

(Renumbered from a duplicate `#36` — original `#36` was the PostgreSQL dev-environment item just above this one.)

## [ ] 37. Beauty Pass

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

## [ ] 40. Deployment

Is this the most deployment process we can make to make sure:

- no deployment downtown with a new release
- quick new releaase

As we are have containers, are using Digital Ocean and their managed services, is there a better way? I'm used to AWS ECS which feels cleaner.

Please analyze.

## [ ] 41. AI

AI is the current FAD. Can we have AI things to the users?

## [ ] 42. Money

How do we make a little bit of money for this application? People use it. Advertisers want it. We want it useful and NOT in the user's face.

Constraint: the homepage tagline is "no tracking, no algorithmic agenda" — programmatic ad networks (Adsense, Carbon, pixel-based attribution) are out. Goal is "cover the $32/mo infra + future Anthropic API spend," not "build a business."

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

## [ ] 43. Filter Feeds

Filter Feeds on the /filter page doesn't work. Please fix.

(Note: there is no `/filter` route — the filter UI lives on `/feeds` via `public/feeds-filter.js` from STUFF #27. The bug investigation paused mid-session; if it still mis-fires in prod, reproduce + capture which input/chip doesn't filter rows.)

## [ ] 45. Sports team follow management

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

**Follow-up gap (separate task)**: recurring sport-sync isn't scheduled on the Droplet. Today the user sees fresh data only when (a) they newly follow a team — eager sync covers that — or (b) the operator manually runs `make sync-sports`. Proper fix: sidekiq-cron or a recurring tick worker.

## [x] 46. /sports/tennis autosyncs on page load

Surfaced from prod (2026-05-18): `/sports/tennis` rendered empty because the `sports_players` table had never been synced on the Droplet. Even after a manual sync, ATP/WTA rankings would go stale within a week.

**Shipped on PR #136 (v0.9.5).** Opportunistic ESPN refresh on page load: when the last sync for a tour is > 12h old (or there's no data at all), the route calls `Providers::ESPN.tennis_rankings` inline and upserts. Adds ~1s to the first request after the TTL window; cached for everyone after. ESPN errors are caught + logged, never raised — the page still renders whatever's in the DB.

The per-tour fetch + slugify + upsert dance moved from `scripts/sync_sports.rb` into `SportsPlayersStore.refresh!(tour:)` + `refresh_if_stale!(tour:)` + `tennis_player_slug(name)` so the route AND the cron share one code path. 9 examples in `spec/sports_tennis_autosync_spec.rb`.

`?skip_refresh=1` bypasses the inline refresh (used by the empty-state spec + manual debugging).

**Related gap that's still open**: a similar autosync for the `/sports` team-score tiles. The eager sync from #45's follow-route covers freshly-followed teams; existing follows still need a recurring tick (or the same on-page-load pattern). Captured under #45's "Follow-up gap" note above.

## [ ] 47. SQLite3

Are we done w SQLite3? If so, can you develop a plan to remove it from the codebase as well as CI.

## [ ] 48. Admin Pages

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
