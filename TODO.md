# TODOs

Informal scratch list of UI / UX / feature ideas. Add new items at the bottom; status moves left → right as work progresses.

**Status lifecycle**: `not implemented` → `in implementation` → `implemented` → `tests` → `merged`

| Stage | Meaning |
|---|---|
| `not implemented` | Idea captured, no code yet. |
| `in implementation` | Code being written; nothing committed. |
| `implemented` | Code written + locally exercised; no tests yet. |
| `tests` | Tests written and passing locally. |
| `merged` | Merged to `main` (with the commit SHA referenced). |

---

## Unified Articles & Podcasts, and UI/UX

**Status: `merged`** — partial scope, in commit `4be54c2`.

The original ask had three parts. After discussion we did the first two and intentionally dropped the third:

- [x] **Visual differentiation between articles and podcasts in the unified `/articles` list.** Each row has a left-gutter glyph: 📄 for articles, 🎧 for podcasts, plus `news-item-{article,podcast}` modifier classes for any future styling fork. The text "PODCAST" badge is gone from list rows (it stays on the article-detail header where it lives in a header context, not a list).
- [x] **Open list rows in a new tab.** The row anchor now carries `target="_blank" rel="noopener"`, so clicking a row opens the article in a new tab and `Cmd-W` returns the user to the list. Turbo respects the `target` attribute, so SPA navigation is unaffected.
- [ ] **Collapse `/podcasts` into `/articles`.** Declined — the show-grid view (one card per subscribed podcast, freshest first) on `/podcasts` is genuinely useful for "what's new from each show today?" and would clutter a unified list. `/articles?kind=podcast` already gives the linear-list view of episodes for users who prefer it.

Tests covering the new icons + open-in-new-tab behaviour live in [spec/podcast_integration_spec.rb](spec/podcast_integration_spec.rb).

---

# Personalization & relevance

There will always be more unread than a user can consume. These items collectively answer "help me find what's worth my time today." Recommended ship order: the signal first (so we have data to work with), then the consumers, then the bulk-triage UX as a parallel track.

## Per-item & per-feed feedback signal

**Status: `merged`** — commit `c8ba317`.

The foundation for the personalisation phases below. Captures explicit user valence on each article + per feed, store it, expose it cheaply to the ranker (Phase 6).

- [x] **Schema**: `read_state.feedback INTEGER NOT NULL DEFAULT 0` (∈ {-1, 0, +1}); `feed_feedback (feed_id PK, weight REAL DEFAULT 1.0, updated_at)` with ON DELETE CASCADE on the feed.
- [x] **UI on /article/:uid**: thumbs-up / thumbs-down forms in the actions row alongside Mark read / Bookmark / Archive. Toggle behaviour (clicking 👍 again clears it).
- [x] **UI on /articles row**: inline 👍 / 👎 affordances revealed on row hover; permanent visible state when the user has voted.
- [x] **UI on /feeds**: per-row +/− pills around a 1.00× weight readout. `FeedFeedbackStore.bump` clamps to [0.25, 3.0].
- [x] **Specs**: 20 examples in [spec/feedback_store_spec.rb](spec/feedback_store_spec.rb) + 19 in [spec/feedback_routes_spec.rb](spec/feedback_routes_spec.rb).

Cold-start safe: an unset signal is treated as 0, identical to pre-Phase-3.

## Relevance-ranked "For You" view on /articles

**Status: `merged`** — commit `a738901`.

Adds a sort option that orders unread by a personalised score instead of `published_at DESC`. The default stays chronological so the existing flow doesn't regress.

- [x] **Score**: `recency_decay × per_feed_weight × (1 + α·positive_overlap) × max(NEGATIVE_FLOOR, 1 − β·negative_overlap)`. Positive corpus = bookmarked + 👍 + passive +1. Negative corpus = 👎 + passive -1 + archived-without-reading. Half-life 48h on the recency decay; α=β=0.5 boost/damp; NEGATIVE_FLOOR=0.4 keeps a single 👎 from hiding a topic.
- [x] **Implementation**: pure-compute scorer in [app/recommendation/for_you.rb](app/recommendation/for_you.rb). Pulls top-20 distinctive tokens from each corpus (reusing `Recommendation.top_keywords` + its stopword list); per-candidate overlap is set-intersection on the candidate's title tokens, saturating at OVERLAP_SAT=5 matches. Title-only tokenization on the candidate side keeps the 500-row scoring window fast (titles average ~60 chars vs. content_text averaging ~5KB).
- [x] **Toggle**: `?sort=relevance` on /articles; "For You" chip in the state-filter row alongside the existing chips. Forces state=unread when active (re-ranking already-read articles is rarely useful).
- [x] **Hard cap on negative weight**: NEGATIVE_FLOOR=0.4 clamps `neg_factor`. A single 👎 can't zero out an article — it just sinks ~60%.
- [x] **Specs**: 19 examples in [spec/for_you_spec.rb](spec/for_you_spec.rb) covering empty-corpus → chronological collapse, positive-corpus boost, negative-corpus damp + floor, per-feed-weight multiplication, 48h half-life decay, overlap saturation, corpus selection (incl. archive+read NOT counting as negative — that's the user filing away, not rejecting), score_window orchestration, and the full route + view-surface.

## AI-assisted daily triage

**Status: `merged`** — module + manual UI in commit `9763085`; persistence + cron + `/triage/:id` in `outten/TODO-049` (this branch).

Claude reads the unread queue + a sample of the user's positive/negative corpus and classifies each unread article into must-read / optional / skip with a one-line rationale.

- [x] **Module**: [`Triage::Claude`](app/triage/claude.rb) — pulls up to `UNREAD_LIMIT=30` recent unread + up to `CORPUS_EXEMPLAR_LIMIT=20` exemplars per side, prompts Claude with a structured-JSON output schema and a defensive parser (strips markdown fences, salvages a `{…}` block from surrounding prose, falls back to "skip everything" with `status: :parse_error` on un-parseable output rather than 500ing).
- [x] **Surface**: `/triage` page with three sections (Must read 🔥 / Optional 👀 / Skip 🗑️). Manual trigger via the Generate button + a "Recent triage runs" table at the bottom of the page. `/triage/:id` revisits a stored historical run. Top nav has a "Triage" link.
- [x] **Cost guard**: input capped at `EXCERPT_CHARS=1000` per unread + `EXEMPLAR_CHARS=200` per corpus exemplar (~32 KB / ~5K input tokens). Uses `claude-sonnet-4-6` per the TODO.
- [x] **Cron**: `make triage` (= `scripts/generate_triage.rb`) runs `Triage::Claude.run` and persists via [`TriageStore`](app/triage_store.rb). Migration `010_triages.sql` adds the `triages` table (must_read / optional / skip stored as JSON arrays so the prompt can evolve without further migrations). POST /triage also persists; status `:unavailable` is the only case that doesn't (no row worth keeping). Browse history at `/triage`; detail at `/triage/:id`.
- [x] **Specs**: 17 examples in [spec/triage_spec.rb](spec/triage_spec.rb) (module + initial routes) + 13 in [spec/triage_store_spec.rb](spec/triage_store_spec.rb) (CRUD, recent/latest, JSON round-trip; persisted-route round-trip incl. unavailable-skips-write).

Depends on the feedback signal (Phase 3) + passive signal (Phase 4) to be useful.

# UX for "drowning in unread"

These don't need a personalisation signal — pure triage UX wins.

## Bulk actions on /articles

**Status: `merged`** — commit `2d45a02`.

Checkbox per row + a sticky toolbar at the top with "Mark read / Mark unread / Bookmark / Archive" applied to the selected rows. Turns "10 minutes of clicking" into "5 seconds of triage."

- [x] Checkbox per `.news-item` (`opacity 0.3` by default, full opacity on row hover, checked, or when any selection is active).
- [x] Sticky toolbar (`#bulk-toolbar`) appears when ≥1 row is selected; shows the selected count + the bulk actions + a "Clear" button.
- [x] Backend: `POST /api/articles/bulk` taking `{ uids: [], action: "read"|"unread"|"bookmark"|"unbookmark"|"archive"|"unarchive" }`. Returns per-uid `results` so the UI can flag any not-found rows; capped at `BULK_UIDS_MAX = 500` per call; de-duplicates the input list.
- [x] Keyboard: shift-click on a checkbox toggles every row between the last-clicked and this one to the new state (Gmail-style range select).
- [x] Specs: 9 examples in [spec/bulk_articles_route_spec.rb](spec/bulk_articles_route_spec.rb) — round-trip, full action whitelist, 400 paths (unknown action / missing uids / invalid JSON), per-uid result shape with mixed valid/invalid uids, batch cap, de-duplication, and `/articles` toolbar surface.

(👎 deferred — depends on the feedback signal from Phase 3.)

## Skim mode

**Status: `merged`** — commit `a91be6c`.

A `/articles?view=skim` query that renders title + cached summary only (no body excerpt, no tags, no meta noise) at a larger font, optimised for fast scan-and-triage. Each row still has the row-link to the full article.

- [x] CSS — `.news-list.skim` modifier hides `.news-meta` and `.news-row-badges`, enlarges `.news-headline`, surfaces a 3-line-clamped summary aligned under the headline.
- [x] Toggle in the page header (chip alongside the state filters); preserves `state` and `kind` filters when toggling.
- [x] Summary precedence: LLM > extractive > 240-char content_text excerpt (with ellipsis on truncation). Implemented as `skim_summary_for` helper in [app/main.rb](app/main.rb).
- [x] `SummaryStore.find_for_ids(article_ids)` — batch lookup so the view doesn't N+1 across the page.
- [x] Specs: 13 examples in [spec/skim_mode_spec.rb](spec/skim_mode_spec.rb) covering chip state on/off + filter preservation, `.news-list.skim` modifier, full summary precedence chain (incl. truncation + empty-content fallback), invalid `?view=` value handling, and the new `find_for_ids` lookup.

## Mute filters: keywords, authors, feeds

**Status: `merged`** — commit `4234961`.

Per-user negative filters that completely hide matching articles from `/articles` (still in the DB, retrievable via search). Different from per-feed weight: muting is a hard hide, weighting is a soft demotion.

- [x] Schema: `mute_rules (kind, value, created_at)` where kind ∈ `{keyword, author, feed}` (CHECK constraint on kind, composite PK on `(kind, value)` so re-adding is idempotent), `008_mute_rules.sql`.
- [x] UI: `/feeds` "Muted" subsection with three small lists + an Add form; `/article/:uid` actions include "Mute author" (when an author is present) + an inline "Mute keyword" input.
- [x] Backend: `ArticlesStore.state_query` adds a single `AND NOT EXISTS (mute_rule that matches)` sub-query that dispatches on `mr.kind`. Vacuously true when `mute_rules` is empty (no perf regression). Keyword match uses LIKE-substring (case-insensitive on ASCII per SQLite's default).
- [x] /search bypasses state_query, so muted articles remain recoverable via FTS5.
- [x] Specs: 30 examples in [spec/mute_rules_spec.rb](spec/mute_rules_spec.rb) covering CRUD + idempotence + whitespace trim + cross-kind composite-key, all three match shapes (keyword substring on title/body, author exact, feed by id), search-bypass, no-op when empty, full route surface (200/302 happy paths, 400 invalid kind/empty value, return_to honoured), and view-surface assertions for /feeds + /article.

## Listened-percent signal for podcasts

**Status: `merged`** — commit `0684bdb`.

Passive feedback: the global player tracks % consumed. ≥80% = treat like 👍; <10% with >30s of playback (i.e. genuine skip, not a 3-second tap) = treat like 👎. Cheap, doesn't require active interaction.

- [x] `tfr.podcast.listened.<uid>` localStorage key tracks max-currentTime-reached so scrubbing back doesn't undo progress.
- [x] On `ended` ⇒ fetch `/api/podcasts/:uid/feedback` with `signal: 1`. On `pagehide` ⇒ `navigator.sendBeacon` with `signal: 1` (≥80%) or `signal: -1` (<10% AND >30s playback). Once-per-load idempotence so `ended` doesn't double-fire on the subsequent `pagehide`.
- [x] `read_state.passive_feedback` column (Phase 4 migration `007_passive_feedback.sql`); explicit-wins guard lives in `ReadStateStore.mark_passive_feedback` so any future caller (cron, batch import) inherits it.
- [x] Specs: 18 examples in [spec/passive_feedback_spec.rb](spec/passive_feedback_spec.rb) covering store-level explicit-wins (passive can't overwrite explicit; persists when explicit clears), validation, and the full route surface (200 happy path, 200 + applied:false when explicit present, 404 unknown uid, 400 missing/invalid signal, 400 malformed JSON, JSON content-type).


## "Read next" suggestion on /article/:uid

**Status: `merged`** — commit `e0cbb2c`.

When the user scrolls past the bottom of the article body, a "Read next" card slides in with the highest-relevance unread match — leverages the For You ranker + the existing FTS5 fallback.

- [x] Card slides in below the article body when the user scrolls past a sentinel. Single recommendation. CSS-driven slide-in via `.read-next-card-visible` class set by a one-shot IntersectionObserver.
- [x] Click → opens in a new tab (matches the `/articles` row behaviour).
- [x] Fallback chain: For You ranker first; if `Recommendation::ForYou.next_after` returns nil (cold start — empty positive corpus), use the top FTS5 "Related" hit. If neither has anything, the card simply isn't rendered.
- [x] Card label flips between "relevance pick" and "related pick" depending on which path produced the suggestion, so the user can see at a glance whether the ranker is in play yet.
- [x] Specs: 9 examples in [spec/read_next_spec.rb](spec/read_next_spec.rb) covering `next_after` (nil article, empty corpus, top-scoring with non-empty corpus, current-article exclusion) + view-surface (FTS5 fallback path, ranker path, no-card empty case, current-article never linked back, new-tab `target="_blank"`).

# Sports — broadening the product beyond technology

The app started as a tech feed reader, but the user reads across categories — sports being the obvious next pillar. The user's specific interests (recorded so the seed catalog isn't generic):

- **Philadelphia Eagles** (NFL)
- **Philadelphia 76ers / Sixers** (NBA)
- **Philadelphia Union** (MLS)
- **New Zealand All Blacks** (men's rugby)
- **New Zealand Black Ferns** (women's rugby)
- **Tennis** — broadly, no team allegiance (ATP, WTA, all four Grand Slams)

Sports is structurally different from articles: it has match results, fixture calendars, league standings, and per-player tracking (especially for individual sports like tennis). The plan below treats news as the "easy" first surface (RSS over the existing pipeline) and structured match/standings data as the foundation that unlocks the score / chart / calendar pages the user asked for.

**Recommended ship order**: S1 + S2 first (immediate value from RSS news through the existing pipeline) → S3 (schema for structured sports data) → S4 (ESPN provider for the leagues it covers — NFL/NBA/MLS) → S5 (`/sports` overview UI) → S6 onward (per-sport detail pages, charts, standings).

## Sports — Phase S1: topic-aware feeds

**Status: `done`** — shipped in commit `a2344e9` (bundled with S2 + S5/S6 news-only v1)

Foundation. The current `feeds` table is undifferentiated; every feed flows into the unified `/articles` pipeline. Adding sports needed a top-level grouping so a user can browse "just sports" / "just tech" and so the For You ranker can scope its corpus per topic later.

Naming: the new column is `topic` (not `category`) because the existing `FeedCatalog` already uses `:category` as the sub-category (`:aggregator` / `:engineering` / `:podcast`). Two-level taxonomy = `:topic` (top-level: technology, sports) → `:category` (sub-level inside that topic).

- [x] **Schema**: `feeds.topic TEXT NOT NULL DEFAULT 'general'` + index, migration `011_feeds_topic.sql`. Backfill all existing rows to `topic='technology'`.
- [x] **Store**: `FeedsStore.add` accepts `topic:` (defaults to `'general'`); `FeedsStore.update` allows it through.
- [x] **Catalog**: `FeedCatalog::TOPICS` constant + `CATEGORY_TO_TOPIC` map + `topic_for(entry)` helper + `by_topic` two-level nest. Topic derived from the existing `:category` so individual entries don't carry both fields.
- [x] **Filter**: `/articles?topic=…` filter via `state_query`'s new `topic:` kwarg (parameterised through an EXISTS sub-query against feeds). Composes with state / kind / view / sort / feed_id / tag / page in `filter_url`. Topic chips render in the state-filter row only when the user has feeds in ≥2 topics.
- [x] **Catalog-add propagates topic**: both `POST /feeds/catalog/add` (form) and the JSON-API equivalent now pass the resolved topic into `FeedsStore.add`. Verified live: subscribing to Bleeding Green Nation via the catalog stores `topic='sports'`.
- [ ] **For You scope**: deferred to a follow-up. With limited corpus today the cross-topic bleed is small; will land after the user has built up sports corpus through use.
- [x] **Specs**: 17 examples in [spec/feeds_topic_spec.rb](spec/feeds_topic_spec.rb) covering store defaults / explicit topic / update; catalog `TOPICS` + `CATEGORY_TO_TOPIC` consistency + `topic_for(category|entry)` + 8-sports-entries census + `by_topic` shape; ArticlesStore topic filter (incl. composes with state filter, empty result on no-match); /articles route surface (rendered list filters, invalid value falls through, chip preserves topic via `filter_url`); catalog-add route (sports url → sports topic, tech url → technology topic).

## Sports — Phase S2: seed the user's sports RSS feeds

**Status: `done`** — shipped in commit `a2344e9` (bundled with S1)

Eight catalog entries verified live (HTTP 200 + valid RSS/Atom signature) covering all six of the user's stated interests. Feeds aren't auto-seeded — adoption is opt-in via the catalog's "+ Add" buttons, matching how the existing tech-podcast catalog works.

Quick, immediate-value win once S1 lands. Curates the user's specific teams as catalog entries with `:category => :sports`. Articles flow through the existing scheduler / parser / search / feedback pipeline — no new code paths.

- [ ] **Eagles** — [Bleeding Green Nation](https://www.bleedinggreennation.com/) is the SB Nation community blog with active beat-writer coverage; SB Nation sites publish RSS at `/rss/index.xml` (verify on add). [PhillyVoice Sports RSS](https://www.phillyvoice.com/rss-feeds/) also covers Eagles among Philadelphia teams.
- [ ] **Sixers** — [Liberty Ballers](https://www.libertyballers.com/) (SB Nation, same `/rss/index.xml` convention). PhillyVoice as a second source.
- [ ] **Union** — [Brotherly Game](http://www.brotherlygame.com/) (SB Nation) + [The Philly Soccer Page](https://phillysoccerpage.net/) (independent, has WordPress RSS).
- [ ] **All Blacks (men's)** — [Stuff Rugby](https://www.stuff.co.nz/sport/rugby) (NZ's largest news site; RSS at `https://www.stuff.co.nz/rss/sport/rugby/`), [RNZ Sport RSS](https://www.rnz.co.nz/rss/sport.xml), [NZ Herald All Blacks](https://www.nzherald.co.nz/sport/rugby/all-blacks/).
- [ ] **Black Ferns** — [allblacks.com Black Ferns](https://www.allblacks.com/teams/black-ferns) (official) + [NZ Herald Black Ferns](https://www.nzherald.co.nz/sport/rugby/black-ferns/). RSS coverage thinner than men's; if no RSS, defer to Phase S4 structured fixtures.
- [ ] **Tennis** — [ATP Tour RSS](https://www.atptour.com/en/media/rss-feed), [ESPN Tennis](https://www.espn.com/tennis/), and Tennis365 (`https://tennis365.com/feed`).
- [ ] **Specs**: catalog entries surface with the right category; subscribed Eagles articles render under `/articles?category=sports`; one-shot `make seed-sports-feeds` script (analogous to `make seed-feeds`).

## Sports — Phase S3: structured-data schema (matches, teams, players, leagues)

**Status: `done`** — shipped in commit `c059411` (bundled with S4, ESPN-only)

News alone isn't enough — the user asked for "scores of recent games, charts of performance in leagues". That requires structured records, not free-text articles. New tables sit alongside the existing schema; no migration of the article tables.

- [ ] **Schema** (`012_sports_core.sql`):
  - `sports_leagues (id, slug, name, sport, source_provider, external_id, country, season_year)` — e.g. `(1, 'nfl', 'NFL', 'football', 'espn', 'nfl', 'US', 2026)`.
  - `sports_teams (id, league_id, slug, name, short_name, location, source_provider, external_id, image_url)` — e.g. Eagles row tied to NFL league.
  - `sports_matches (id, league_id, home_team_id, away_team_id, scheduled_at, status, home_score, away_score, period, venue, source_provider, external_id, last_synced_at)` — `status ∈ {scheduled, live, final, postponed, cancelled}`. Composite UNIQUE on `(source_provider, external_id)` for idempotent upserts.
  - `sports_players (id, sport, slug, full_name, country, image_url, source_provider, external_id)` — primarily for tennis follows. NULL `team_id` for individual-sport players.
  - `sports_follows (kind, value, created_at)` — analogous to `mute_rules`; `kind ∈ {team, player, league}`. The user's "I follow the Eagles + Black Ferns + Iga Świątek" list. Drives every UI surface below.
- [ ] **Stores**: `SportsLeaguesStore`, `SportsTeamsStore`, `SportsMatchesStore`, `SportsPlayersStore`, `SportsFollowsStore` — same hash-row return shape as the existing stores.
- [ ] **Specs**: schema round-trip; idempotent upsert by `(source_provider, external_id)`; cascade behaviour when a league is removed; follows CRUD.

## Sports — Phase S4: data providers — ESPN (NFL/NBA/MLS + intl rugby) + TheSportsDB (deferred)

**Status: `done`** — shipped in commit `c059411` (bundled with S3), ESPN-only; TheSportsDB still deferred (free-key poisoned, Patreon required)

Originally planned as ESPN + TheSportsDB. Shipped as **ESPN-only** in this PR — TheSportsDB's free tier key '3' has been hijacked at the source (every search endpoint returns Arsenal regardless of query, confirmed live). The Patreon-tier $9/mo dedicated key still works, so TheSportsDB integration is a future follow-up gated on either the user opting into the paid tier or another free rugby/tennis provider surfacing.

- [x] **`Providers::ESPN`** ([reverse-engineered public endpoints](https://gist.github.com/akeaswaran/b48b02f1c94f873c6655e7129910fc3b)). Free, no auth, no documented rate limit. Two entry points:
  - `team_schedule(sport_path:, team_external_id:)` for NFL / NBA / MLS — full season schedule per team in one call. Used for Eagles / Sixers / Union.
  - `league_scoreboard(sport_path:, dates:)` for international rugby — the team-schedule endpoint 500s on rugby; scoreboard works and the sync filters to the followed team. Covers All Blacks (men's intl tests).
  - Defensive normalization: per-event `rescue StandardError` so one weird row doesn't poison a batch. Status mapping covers ESPN's full vocabulary (scheduled / in-progress / halftime / final / postponed / cancelled / forfeit) collapsed into our 5-status taxonomy.
  - Score extraction handles both shapes: `score: {value, displayValue}` (current) and bare-string `score: "24"` (legacy).
- [ ] **`Providers::TheSportsDB`** — **deferred** until either (a) the user opts into the $9/mo Patreon API key or (b) another free provider surfaces for women's intl rugby + tennis tournament draws. Verified at PR-time that the free key '3' is poisoned (every `searchteams.php` call returns Arsenal). Black Ferns + tennis structured data therefore aren't synced yet — but their RSS news already flows through the existing pipeline, so the user-facing miss is small.
- [x] **Cron-style ingestion**: `make sync-sports` (= [scripts/sync_sports.rb](scripts/sync_sports.rb)) walks `sports_follows` (kind=team), dispatches per league's sport (team_schedule for football/basketball/soccer, league_scoreboard + filter for rugby), upserts into `sports_matches`. Idempotent; auto-creates opponent team rows so match displays have both sides populated even when the user only follows one team in a league.
- [x] **Seed**: `make seed-sports-data` (= [scripts/seed_sports_data.rb](scripts/seed_sports_data.rb)) populates 4 leagues + 4 teams + 4 follows for the user's interests. Idempotent. Verified live: 42 matches synced across Eagles (17), Sixers (14), Union (11), All Blacks (0 — current intl test window has no NZ fixtures).
- [x] **Specs**: 17 examples in [spec/sports_espn_spec.rb](spec/sports_espn_spec.rb) — `normalize_event` happy + edge cases (Hash score, flat-string score, missing score, nil event), full STATUS_MAP coverage, `team_schedule` URL building + 200/500/parse-error/raise paths, `league_scoreboard` URL with/without `dates`. HTTP fully stubbed via `http_get:` injection.

Sources: [ESPN endpoint catalogue](https://gist.github.com/akeaswaran/b48b02f1c94f873c6655e7129910fc3b), [pseudo-r/Public-ESPN-API](https://github.com/pseudo-r/Public-ESPN-API), [Zuplo's ESPN guide](https://zuplo.com/learning-center/espn-hidden-api-guide).

## Sports — Phase S5: `/sports` overview page

**Status: `done` (news-only v1)** — shipped in commit `a2344e9` (bundled with S1+S2)

The user asked: "Should we create a top level Sports page that aggregates the sports info?" The answer was yes, but the structured data (live scores, results, upcoming fixtures) won't exist until S3+ ships. So this PR delivers the **news-only** version of S5 — per-sport sections with subscribed feeds + recent articles — and the Live / Results / Upcoming sections will land on the same page once the structured-data schema arrives.

- [x] **News-only layout shipping now**: per-sport sections (NFL / NBA / Soccer / Rugby / Tennis) — each renders subscribed feeds (linked) + the 8 most recent articles in that sport. Sections that have neither subscribed feeds nor articles are suppressed, so a single-sport user doesn't see four empty placeholders. Plus an "Other sports feeds" section for any sports-tagged URLs not in the curated catalog.
- [x] **Top nav** gains a "Sports" link.
- [x] **Empty state**: "No sports feeds subscribed yet" + pointer to /feeds catalog.
- [x] **Sports podcasts surface here too** — they're tagged with the sport's category (`:nfl`/`:nba`/`:soccer`/`:rugby`/`:tennis`), so audio shows alongside news. The 8-feed news catalog grew to 14 (+ 6 podcasts: Bleeding Green Nation Pod, Sixers Talk, All Three Points, Aotearoa Rugby Pod, Good/Bad/Rugby AusNZ, The Tennis Podcast).
- [x] **Specs**: 7 examples in [spec/sports_route_spec.rb](spec/sports_route_spec.rb) — empty state, per-sport section composition, article-link round-trip, suppressing empty sections, "Other" bucket for uncatalogued URLs, header counts, top-nav highlight.
- [ ] **Live now / Recent results / Upcoming sections** — defer to the same `/sports` route once Phase S3 (structured-data schema) + Phase S4 (provider sync) land. Same page, just three additional sections at the top.

## Sports — Phase S6: per-team detail page + performance chart

**Status: `done` (news-only v1)** — shipped in commit `a2344e9` (bundled with S1+S2+S5)

The user asked for "buttons in the Executive Summary of the area to filter on sports team … with simple, but nice articles on them". That's the per-team detail page; structured-data parts (matches, charts, standings) wait on Phase S3+.

- [x] **`/sports/team/:slug`** route — renders articles + podcast episodes from every catalog feed_url that belongs to the team AND is subscribed by the user. Uses the same vertical-card layout as `/sports`.
- [x] **`SportsTeams` data module** ([app/sports_teams.rb](app/sports_teams.rb)) — five teams covering the user's interests (Eagles, Sixers, Union, NZ Rugby/All-Blacks, Tennis). Each team carries slug / name / sport / emoji / blurb / `feed_urls` (intersected with `FeedsStore.find_by_url` to figure out actual subscriptions). Catalog is the single source of truth — every `feed_url` in TEAMS must already exist in `FeedCatalog::CATALOG` (asserted in the spec).
- [x] **Team button strip** in the `/sports` TOC — second row of pills with team logos/emoji + short name. Only renders teams with ≥1 subscribed feed (no point linking to a team page that's empty). Click → `/sports/team/<slug>`.
- [x] **Logos**: emoji defaults today (🦅 Eagles / 🏀 Sixers / ⚽ Union / 🏉 All Blacks / 🎾 Tennis). Each team carries an `:image_url` field that's `nil` for now — a follow-up PR can drop in real logo URLs without a schema change.
- [x] **Empty state** when team is followed in TEAMS but no feeds subscribed: shows the catalog candidates the user could add ("Bleeding Green Nation — Multi-show audio network…", etc).
- [ ] **Last-N matches table + win/loss chart + league record** — defer to S3+ once structured match data exists. Same route, additional sections.
- [x] **Specs**: 14 examples in [spec/sports_team_route_spec.rb](spec/sports_team_route_spec.rb) covering the data module (TEAMS shape, all feed_urls catalog-resolvable, `find` happy + nil paths, `subscribed_feeds_for` intersection), the route (header rendering, articles flow, empty state, 404 on unknown slug, multi-feed chronological merge), and the /sports TOC team-row (suppress when no subs, render only teams with ≥1 sub).

## Sports — Phase S7: per-sport landing pages + tennis player follows

**Status: `done` (tennis-only v1)** — shipped in commit `48e73e6`

User asked specifically for tennis rankings + drill-down. Shipped that as the first slice of S7 — per-sport landing pages for the team-based sports (rugby / NFL / NBA / MLS) are deferred since their existing `/sports/league/:slug` + `/sports/team/:slug` already cover the team-centric mental model.

- [x] **Tennis rankings landing** (`/sports/tennis`): two side-by-side tables — ATP top N + WTA top N. Each row: rank, headshot (circle), player name (linked), country (with ESPN flag PNG), points, week-over-week trend (↑/↓ with delta, color-coded). `?limit=N` tunable, default 50, clamped 1..150. Empty state when nothing synced.
- [x] **Player detail page** (`/sports/player/:slug`): player headshot, country flag, current rank + week-over-week movement, points, tour, link out to ESPN player card (career stats, head-to-heads). Slugs are auto-derived from the display name (Unicode-decomposed → ASCII; `tennis_player_slug` helper in `scripts/sync_sports.rb`).
- [x] **Schema** (`015_sports_players_tennis.sql`): extends the existing `sports_players` skeleton with `tour`, `current_rank`, `previous_rank`, `points`, `trend`, `headshot_url`, `flag_url`, `last_synced_at`. Indexed by `(tour, current_rank)` for the rankings page's single-sorted-scan-per-tour query.
- [x] **Provider**: `Providers::ESPN.tennis_rankings(tour:)` — wraps `/sports/tennis/<tour>/rankings`. Validates tour ∈ {atp, wta} (raises ArgumentError on bad input — propagates through the rescue). Defensive on JSON shape: handles flag/headshot as either flat string or `{href}` hash.
- [x] **Sync**: `make sync-sports` now also pulls ATP + WTA rankings (top 150 each). Cheap (one HTTP per tour). Verified live: 300 player rows synced (Sinner #1 ATP, Sabalenka #1 WTA).
- [x] **Entry point**: `/sports` header subtitle gains a "🎾 Tennis rankings →" link, alongside Calendar + All sports articles.
- [ ] **Player follows** — deferred. The schema supports `sports_follows` with kind=player; the UI wiring (search-by-name + follow/unfollow form) is the next obvious enhancement once the rankings surface gets real use.
- [ ] **Per-sport landings for team sports** (rugby / NFL / NBA / MLS) — deferred. The existing `/sports/league/:slug` + `/sports/team/:slug` pages already serve the team-centric mental model; a separate per-sport hub would mostly duplicate them.
- [ ] **Live scoreboard panel for active Grand Slam draws** — needs TheSportsDB tournament endpoints (gated on a working free key — see Phase S4 deferral note). Defer.
- [x] **Specs**: 19 examples in [spec/sports_tennis_spec.rb](spec/sports_tennis_spec.rb) — store upsert + idempotence + `top_ranked` (tour scoping, limit, NULL-rank exclusion); ESPN provider happy + flat-shape variants + tour validation + error paths; `/sports/tennis` empty + populated + linking + trend arrows + `?limit=` clamp; `/sports/player/:slug` happy + 404 + movement; `/sports` header tennis link.

## Sports — Phase S8: league standings tables

**Status: `done`** — shipped in commit `bad8911`

`/sports/league/:slug` (e.g. `/sports/league/nfl`) — full league table per league the user follows.

- [x] **Schema** (`014_sports_standings.sql`): `sports_standings` table indexed by `(league_id, group_name, position)`, idempotent upsert on `(source_provider, league_id, group_name, team_id)`. Captures position / W-L-T / win_percent / points_for / points_against / point_differential / games_behind / streak / playoff_seed / last_synced_at.
- [x] **Provider**: `Providers::ESPN.standings(sport_path:)` walks ESPN's nested children/standings tree and flattens to `[StandingsGroup{group_name, entries:[StandingsEntry...]}]`. Defensive — per-leaf rescue, returns `[]` on HTTP/parse/network failures.
- [x] **Sync**: `make sync-sports` now also pulls standings per league after match data, auto-creates any standings-only team rows that the schedule sync missed. Verified live: 92 standings rows synced (2 NFL conferences × 16 teams + 2 NBA conf × 15 + 2 MLS conf × 15).
- [x] **Page**: `/sports/league/:slug` renders all groups inside the league as a `data-table`, followed teams highlighted (`.sports-standings-followed`, ★). Each row links to `/sports/team/:slug`. Empty state when no standings synced yet.
- [x] **TOC entry point on `/sports`**: third pill row "By league:" with one pill per league that has synced standings (no followed-team requirement, so globally-interesting tournaments like FIFA World Cup show even when the user doesn't track a specific team).
- [x] **Rugby Championship for the All Blacks**: the original Phase S3 seed put All Blacks in `intl-rugby` (rugby/164205), which doesn't expose standings. Replaced with `rugby-championship` (rugby/244293) — the proper 4-team annual table (NZ + AUS + RSA + ARG). All Blacks now has a synced standings row (#2 in the current snapshot, 159 PF / 151 PA). One-time cleanup in the seed script removes the legacy `intl-rugby` league + its cascade-orphaned matches.
- [x] **FIFA World Cup**: seeded as a league but with no followed team (per the user's "we are not tracking" note). 12 groups × 4 teams synced. Browseable at `/sports/league/fifa-world` and surfaced in the "By league:" pill row. Match sync is follow-gated, so no World Cup matches land in `sports_matches` until the user follows a national team.
- [x] **Standings sync widened**: previously gated on followed-team-in-league; now syncs every seeded ESPN league. Cheap (one HTTP per league) and required for the World Cup case.
- [x] **Inline standing line on the team detail page**: `/sports/team/:slug` header now carries a "National Football Conference · 3rd (11–6) · streak L1 · Full standings →" subtitle when standings exist. New `position_suffix` helper for the ordinal (1st/2nd/3rd/…/11th/12th/13th/21st/etc).
- [ ] **Division-level drill-down** (e.g. NFC East under NFC) — deferred. ESPN's main `standings` endpoint serves at the conference level; division standings need a separate endpoint with a `level=3` query param (probed but not wired). Conference-level is enough for v1.
- [ ] **Per-tile inline standing line on the score-tiles strip** — deferred to a small follow-up. The team detail page already shows it; adding to tiles is purely a layout question.
- [x] **Specs**: 23 examples in [spec/sports_standings_spec.rb](spec/sports_standings_spec.rb) — store CRUD + idempotent upsert + lookups, ESPN provider tree-walk + entry normalization + error paths, route happy + 404 + empty-state, team subtitle render + omit-when-empty, `position_suffix` ordinals across the full set including the 11/12/13 special case.

## Sports — Phase S9: calendar / upcoming + iCal export

**Status: `done`** — shipped in commit `7ccb118`

- [x] **`/sports/calendar` page**: next 30 days of scheduled (and live) matches across every followed team, grouped by local day. `?days=N` tunable (clamped 1..365). Each fixture renders time + matchup (logo + name) + league + venue. Followed-team chips link to `/sports/team/:slug`; auto-created opponents render as plain spans (no broken link).
- [x] **iCal export**: `/sports/calendar.ics` returns `Content-Type: text/calendar` with a proper `Content-Disposition` filename. RFC 5545: CRLF line endings, escaped commas/semicolons/newlines in TEXT properties, UTC `DTSTART`/`DTEND` with `Z` suffix. One `VEVENT` per match with `UID` / `DTSTAMP` / `DTSTART` / `DTEND` / `SUMMARY` / `LOCATION` / `DESCRIPTION` / `STATUS` (CONFIRMED for live, TENTATIVE for scheduled). DTEND duration is per-sport heuristic — football 3.5h, basketball 2.5h, soccer 2h, rugby 2h, default 2.5h.
- [x] **Subscribe-callout** at the top of `/sports/calendar` with the `.ics` URL and a "Download once" alternative for one-shot snapshots. Apple Calendar / Google Calendar both honour the standard subscription URL flow.
- [x] **Entry point**: `/sports` header subtitle gains a "Calendar →" link, alongside the existing "All sports articles →". No top-nav addition (the sports area already has its own nav).
- [x] **Store**: `SportsMatchesStore.upcoming_for_followed_teams(days_forward:, now:)` — single SQL query joining sports_matches → sports_teams → sports_follows, filters by `status IN ('scheduled', 'live')` AND scheduled within `[now, now+days_forward]`.
- [x] **Specs**: 20 examples in [spec/sports_calendar_spec.rb](spec/sports_calendar_spec.rb) — store window/status/follow filters + chronological ordering, view empty/subscribe/grouped/clamp paths, iCal RFC 5545 structure (CRLF, headers, escapes, status mapping, DTEND duration math), `/sports` header link.

## Sports — Phase S10: cross-category personalization

**Status: `done`** — shipped via #58 on 2026-05-09

The For You ranker shipped in Phase 6 was scoped globally. With sports + tech in the same DB, the corpus needs scoping (already added in Phase S1) AND the AI triage (`Triage::Claude`) should run per-category by default — "what should I read in tech today" and "what's important in sports today" are different questions.

- [x] `/articles?sort=relevance&topic=sports` ranks within sports only (and same for tech). `Recommendation::ForYou.score_window` + `corpus_terms` + `positive_corpus` + `negative_corpus` all accept `topic:` and conditional-JOIN onto `feeds` to scope. Helper `sanitize_topic_filter` whitelists `technology|sports|general` to prevent SQL surprises.
- [x] `/triage?topic=sports` runs a sports-only triage. `Triage::Claude.run(topic:)` scopes both unread fetch + corpus exemplars. UI: topic chips at page header (`all topics | technology | sports`) with active-state highlighting + the Generate form carries the active topic via hidden input.
- [x] **Daily cron — per-topic runs**: shipped via outten/TODO-058. `scripts/generate_triage.rb` now loops over `TRIAGE_TOPICS = [nil, 'technology', 'sports']` and persists one `triages` row per topic. Migration 017 adds the `topic` column; `TriageStore.recent(topic:)` filters; the Recent runs table on `/triage` shows a Topic column.
- [x] **Specs**: 11 examples in [spec/topic_scoping_spec.rb](spec/topic_scoping_spec.rb) — `corpus_terms` topic restricts/unscoped legacy union, `score_window` topic, `Triage.run` topic restricts unread + corpus, `/articles?sort=relevance&topic=` route, `/triage` chip rendering + active state + carrying via Generate form. Plus 6 examples in [spec/triage_store_spec.rb](spec/triage_store_spec.rb) (topic round-trip + .recent filtering + Result.topic plumbing) and 2 in [spec/generate_triage_cron_spec.rb](spec/generate_triage_cron_spec.rb).

## Sports — Phase S7 follow-up: tennis player follows

**Status: `done`** — shipped via #58 on 2026-05-09

Phase S7 shipped tennis rankings + per-player detail. The follow-up adds first-class follows for individual players (not just teams), so the user can pin Sinner/Alcaraz/Sabalenka and see them surface above the rankings table.

- [x] `POST /sports/players/follow` + `POST /sports/players/unfollow` — idempotent (re-follow / re-unfollow no-op), 404 on unknown slug, 400 on missing slug, honours `return_to`.
- [x] `★`/`☆` toggle button on every rankings row in `/sports/tennis` — yellow when active, plain hollow star otherwise. Each row's form posts to `follow` or `unfollow` based on current state with `return_to=/sports/tennis`.
- [x] **My followed players callout** at the top of `/sports/tennis`, gated on `(@followed_players || []).any?` — sorts by `current_rank` ascending, shows headshot + tour + country.
- [x] Follow/unfollow toggle on `/sports/player/:slug` detail page with `★ Followed` / `☆ Not followed` heading.
- [x] **Specs**: 9 examples in [spec/tennis_follows_spec.rb](spec/tennis_follows_spec.rb) — POST happy/idempotent/404/400/return_to, unfollow happy/idempotent, rankings ☆-when-empty + ★-when-followed + sorted callout, detail-page toggle in both states.

## Sports — Phase S7 follow-up #2: articles-mentioning-entity surface

**Status: `done`** — shipped via PR #59

Following a player or team only pinned them to their topical landing page; nothing in the article stream changed. This follow-up surfaces "articles mentioning Sinner" / "articles mentioning Eagles" on each detail page, populated by an FTS5 phrase MATCH cache.

- [x] Migration `016_sports_entity_articles.sql` — new polymorphic join table `sports_entity_articles (kind, entity_id, article_id, matched_at)` with PK on `(kind, entity_id, article_id)` + ON DELETE CASCADE on article. New `articles_indexed_at` column on `sports_players` + `sports_teams` for cache freshness.
- [x] `SportsEntityArticlesStore` — `refresh_for(kind:, entity_id:, name:)` runs FTS5 phrase MATCH on the entity's name, upserts hits via `INSERT OR IGNORE`, stamps `articles_indexed_at`. Skips work when within TTL (default 1h, override via `force: true`). `for_entity(kind:, entity_id:, limit:)` reads the cached list ordered by `published_at DESC`.
- [x] `/sports/player/:slug` — refreshes-if-stale on every visit, renders **Articles mentioning {full_name}** section with empty-state copy.
- [x] `/sports/team/:slug` — same pattern, but the section only renders when there's at least one cached hit (the page already has a feed-curated list — empty mention block would be visual noise).
- [x] **Specs**: 8 examples in [spec/sports_entity_articles_spec.rb](spec/sports_entity_articles_spec.rb) — store happy/idempotent/TTL-skip/phrase-strict/unknown-kind, team-name caching, route renders + empty-state copy.

---

## Multi-user — Phase A1: Auth wall (passkey-only, consumer-facing)

**Status: ✅ shipped** — `a9e5032` (#88). Passkey-only sign-up + sign-in, recovery codes, auth wall middleware. Original Entra ID plan replaced by consumer passkey direction (STUFF #22).

> **Historical note (kept for design rationale).** The detailed planning below documents the state-of-the-plan at the time A1 was implemented. Several "deferred" items have since shipped (notably multi-passkey UI, account deletion, recovery-code regeneration — all in the account-management follow-up). See "Multi-user — open follow-ups" below for the current punch list.

**Pivot 2026-05-13:** the original A1 plan targeted an enterprise rollout against Microsoft Entra ID for a single company tenant. STUFF.md #22 changed the direction — this is a **consumer-facing app now**, anyone on the internet can sign up. Auth provider, recovery story, and cost profile all change. Phase A2 (per-user data split) is unaffected — that work is provider-agnostic.

The app is single-user today. Phase A1 ships the auth wall — passkey sign-up + sign-in, a `users` table, sessions, recovery codes — but **does not yet split per-user data**. All existing data stays shared; the first person to sign up becomes user 1 and inherits Todd's bookmarks/state. This lets us land auth as one focused PR and start A2 (per-user data split) only after the auth wall has been kicked in real use.

### Why passkey-only (no email, no SMS, no password)

| | Email/Password | SMS (Text) | **Passkey (WebAuthn)** ✓ |
|---|---|---|---|
| Phishing resistance | Low (reused passwords, AITM) | Low (SIM swap) | **Very high** — origin-bound, no shared secret |
| UX after first login | Type credentials | Wait for SMS, type 6-digit | Tap fingerprint / Face ID (~1s) |
| Cost / login | Free (but need email infra for recovery) | $0.01–0.05 per SMS, scales linearly | **Free**, no per-login cost |
| Privacy | Email collected | Phone number collected | **Nothing collected** beyond a username |
| Recovery | Email reset link | "Lost my phone" is brutal | Platform sync (iCloud/Google/Bitwarden) + one-time recovery codes |
| Implementation | Moderate | High (Twilio + per-country deliverability) | Moderate (`webauthn` gem) |

User explicitly nixed email (any flavour) and SMS, so **passkey-only with recovery codes** is the path. No external services. No per-message cost. Cleanest privacy story of the three.

### What ships in the Phase A1 PR

**Migrations**
- `019_users.sql` — `users (id, username TEXT UNIQUE NOT NULL, display_name TEXT, created_at, last_seen_at)` + index on `username`.
- `020_webauthn_credentials.sql` — `webauthn_credentials (id, user_id REFERENCES users(id) ON DELETE CASCADE, credential_id TEXT UNIQUE NOT NULL, public_key BLOB NOT NULL, sign_count INTEGER NOT NULL DEFAULT 0, transports TEXT, label TEXT, created_at, last_used_at)`. Multiple credentials per user (so the user can register a passkey on phone + laptop).
- `021_recovery_codes.sql` — `recovery_codes (id, user_id REFERENCES users(id) ON DELETE CASCADE, code_hash TEXT UNIQUE NOT NULL, consumed_at TIMESTAMP)`. 10 codes generated at signup, each usable once.

**Stores**
- `app/users_store.rb` — `find_by_username`, `create(username:, display_name:)`, `touch_last_seen!(id)`.
- `app/webauthn_credentials_store.rb` — `for_user(user_id)`, `register!(user_id:, ...)`, `bump_sign_count!(credential_id, n)`.
- `app/recovery_codes_store.rb` — `mint_for!(user_id, n:)` (returns plaintext codes once), `consume!(user_id, plaintext_code)`.

**Helpers + middleware**
- `app/auth.rb` — `current_user`, `signed_in?`, `require_signed_in!`; loads `dotenv` in dev/test.
- Before-filter on every route: public allowlist (`/`, `/about`, `/health`, `/metrics`, `/auth/*`, `/sign-up`, `/sign-in`, static assets) — everything else 302 → `/sign-in?return_to=<path>`.

**Views**
- `views/sign_up.erb` — "Pick a username, register a passkey." On success, full-screen modal lists 10 recovery codes with a "Download as text" button and a "I've saved these" confirm.
- `views/sign_in.erb` — username field + "Sign in with passkey" button + a "Use a recovery code" link.
- Layout header: "Signed in as {display_name or username} ▾" with logout link.

**Routes** (all JSON for the WebAuthn ceremonies; HTML for the page shells)
- `GET /sign-up` / `GET /sign-in` — page shells.
- `POST /api/auth/register/options` — server emits `PublicKeyCredentialCreationOptions`; stores the challenge in the session.
- `POST /api/auth/register/verify` — verifies the attestation, creates `users` + `webauthn_credentials` row, mints 10 recovery codes, returns them in the response body once.
- `POST /api/auth/login/options` — for a given username, emits `PublicKeyCredentialRequestOptions` listing that user's registered credentials.
- `POST /api/auth/login/verify` — verifies the assertion, bumps `sign_count`, sets `session[:user_id]`.
- `POST /api/auth/recovery` — username + one recovery code → consume + sign in.
- `POST /sign-out` — clears session.

### Library + tooling

| Concern | Choice | Why |
|---|---|---|
| WebAuthn server library | [`webauthn`](https://github.com/cedarcode/webauthn-ruby) | Maintained, used by Mastodon + GitLab. Handles registration + authentication ceremonies, attestation verification, sign-count check. |
| Browser-side ceremony | Native `navigator.credentials.create()` / `.get()` — no library | First-party browser API; available on 95%+ of active browsers. Tiny shim in `public/auth.js` (~80 LoC) to base64url-encode/decode + post JSON. |
| Recovery code hashing | `OpenSSL::HMAC.hexdigest('SHA256', SESSION_SECRET, code)` | No reason to use bcrypt — codes are high-entropy, single-use, and the perf cost of bcrypt-each-check matters when a user has 10 of them. |
| Session storage | `Rack::Session::Cookie` (signed, encrypted) | Already used by `Sidekiq::Web`; no new infra. |
| Secrets in dev | `dotenv` gem + the existing `.env` (already gitignored) | Loads only in `RACK_ENV=development|test`; prod reads from real env vars. |
| CSRF | `rack-protection` (already pulled in) | The `/api/auth/*` JSON endpoints need an exemption (CSRF tokens vs WebAuthn challenges are belt-and-suspenders); auth POSTs from the same origin are still bounded by the SameSite cookie. |

`.env` during dev (no third-party secrets needed):
```
SESSION_SECRET=<64-byte hex>
WEBAUTHN_RP_NAME=Tech Feed Reader
WEBAUTHN_RP_ID=localhost           # in prod: your bare domain (e.g. tfr.example.com)
WEBAUTHN_ORIGIN=http://localhost:4567   # in prod: https://tfr.example.com
```

`.credentials` (existing) keeps `ANTHROPIC_API_KEY` — no migration needed.

### Decisions (locked 2026-05-13)

| Question | Choice |
|---|---|
| Auth method | **Passkey-only** (WebAuthn). No password, no email, no SMS. |
| Identity field | **Username** (unique, user-chosen at signup). No email stored. |
| Recovery | **10 one-time recovery codes** generated at signup, shown once, hashed at rest. Account is locked if user loses all passkeys + all codes — documented explicitly on the signup screen. |
| First-time-user behaviour | **Auto-create user + sign in** — first user (Todd) becomes user_id=1 and inherits the existing single-user data. |
| Sign-up open / closed | **Open for now**. Once we hit a real cost ceiling we can add a per-day signup rate-limit or invite codes. |
| Recovery-code algorithm | 10 codes, each 5 groups of 4 base32 chars (e.g. `XK4P-9MWZ-...`). HMAC-SHA256 with `SESSION_SECRET` as the storage hash. |
| Account deletion | Out of scope for A1. POST `/account` route in a follow-up; until then it's a manual DB delete. |

### What Phase A1 does NOT do (intentional deferral)

- **No per-user data scoping** — every signed-in user sees the shared "owner" bookmarks/feeds/tags. This is the auth-wall model: gated, but everyone shares state. A2 handles the split.
- **No admin pages, no user management UI, no roles** — flat permissions; everyone signed in is "a user."
- **No email anywhere** — explicit user direction. Recovery story is "save the codes, register passkeys on multiple devices, use platform sync (iCloud Keychain / Google Password Manager / 1Password / Bitwarden)."
- **No social login / no SSO providers** — explicit pivot away from this.
- **No multi-passkey UI v1** — registration only adds the first passkey at signup. Add-another-passkey-on-this-device-too can come in a follow-up; the schema already supports it.

### Open questions (before opening the Phase A1 PR)

- **`WEBAUTHN_RP_ID` for prod**: needs to be the bare domain we'll deploy on. Until we have it, dev uses `localhost`.
- **Backup strategy for `webauthn_credentials` + `recovery_codes`**: tied to the larger "deploy this somewhere" decision. SQLite-on-S3 with Litestream replication (per STUFF.md #11) covers it.

---

## Multi-user — Phase A2: per-user data split

**Status: ✅ shipped** — `7b1533a` (#89, A2.0) + `7b7bcca` (#90, A2.1 + A2.2).

Per-user data split via migration `022_a2_per_user_data.sql` (composite PKs or `(user_id, …)` unique constraints + `ON DELETE CASCADE` FKs). Every store method now takes `user_id` explicitly; 109 `current_user_id` call-sites in [app/main.rb](app/main.rb). Tables covered:

1. ✅ `read_state` + `feed_feedback` — composite PK `(user_id, …)`.
2. ✅ `mute_rules`, `tags` — composite PK / unique-per-user.
3. ✅ `sports_follows`, `triages`, `digests` — `user_id` columns.
4. ✅ `feeds` — option (a) chosen: shared catalog stays; new `user_feed_subscriptions` bridge table.

Cross-user isolation regression suite in [spec/cross_user_isolation_spec.rb](spec/cross_user_isolation_spec.rb).

---

## Multi-user — open follow-ups

Phase A1 + A2 deferrals + production gating. Not blockers for the auth/data split themselves; ordered by user-visible value.

1. ✅ **Account management page** — `/account` with profile + passkey list / add / revoke + recovery-codes regenerate + account deletion (STUFF #29 follow-up; landed alongside this TODO refresh).
2. ✅ **First-time onboarding** — `/welcome` topic-chip picker for new signups (PR #100).
3. **Production `WEBAUTHN_RP_ID`** — locked to `tmoneystuff.com`. Wired in **Phase D6** of the deploy plan below.
4. **Admin user list** — small admin-namespace page showing signed-up accounts with last-seen-at, useful when signups open up.
5. **Per-user data export** — GDPR-style "download my data" endpoint. Only matters at scale.
6. **Open-signups rate limit** — per-day signup-rate cap or invite codes; only needed if abuse appears.

---

## Deploy — Phase D: Digital Ocean (STUFF #31)

**Source of truth: [DEPLOYMENT.md](DEPLOYMENT.md).** That doc holds the live phased execution plan (Phase 0 / 1 ✅ / 2 ✅ / 3 / 4), the hosting trade-offs, and the pre-deploy blockers (LLM cost containment, WebAuthn domain binding, operational basics). Don't duplicate it here.

**Status at a glance** (read DEPLOYMENT.md for the detail):

- ✅ **Phase 0** — manual setup (DO account, tokens, domain, NS, SSH, Spaces keys, zone in DO panel). Done 2026-05-17.
- ✅ **Phase 1** (codebase prep) — LLM rate limiting (#103), Dockerfile + docker-compose + Caddyfile (#104), per-IP RateLimiter (#105). Merged.
- ✅ **Phase 2** (Terraform scaffold) — `terraform/` directory provisioning a single Droplet + firewall + DO Spaces for backups (#106). Rewritten to DO DNS + feeder subdomain (#109/#110).
- ✅ **Phase 3** — `terraform apply` + cutover. Live at https://feeder.tmoneystuff.com (2026-05-17).
- ❌ **Phase 4** (SQLite backups) — **skipped**. User opted to do the PG migration instead of building SQLite backup tooling that becomes throwaway. Data-loss window between now and Phase 5 cutover is accepted.
- ⏳ **Phase 5** — PostgreSQL migration (5 PRs + manual cutover). See DEPLOYMENT.md → "Phase 5" for sub-phase plan (D-PG-1 adapter → D-PG-2 migrations + CI matrix → D-PG-3 store audit → D-PG-4 Terraform cluster → D-PG-4.5 data dump script → D-PG-5 cutover).

**Architecture (per DEPLOYMENT.md):** single DigitalOcean Droplet running Docker Compose (web + sidekiq + redis); **Caddy** in front for HTTPS via Let's Encrypt; **SQLite for v1.0** (Postgres deferred to v1.1 — DEPLOYMENT.md "Database" section has the full migration scope). Total provisioned cost ≈ **~$17/mo** (Droplet + Spaces).

### Decisions locked during this session

These now also live in DEPLOYMENT.md's "Locked decisions" block — duplicated here for the TODO reader.

- **Domain**: **`tmoneystuff.com`** registered at **Namecheap**. NS records pointed at `ns1.digitalocean.com` / `ns2.digitalocean.com` / `ns3.digitalocean.com` — **DigitalOcean DNS** is source of truth. The user plans to host multiple apps on this zone, so the apex is intentionally left untouched by this app's Terraform.
- **App serving**: **`feeder.tmoneystuff.com`** (subdomain). Terraform manages a single A record at `feeder.${var.domain}` → Droplet IP. The apex and any other subdomains belong to other apps.
- **Production `WEBAUTHN_RP_ID`**: **`feeder.tmoneystuff.com`** — bound to the subdomain where this app actually serves, so passkeys for this app stay separate from any future apps on other subdomains of the same zone. Closes follow-up #3 in "Multi-user — open follow-ups" above.
- **DNS provider**: **DigitalOcean** (not Cloudflare). The Terraform was rewritten away from `cloudflare_record` to `digitalocean_record` in the same PR that pinned the subdomain.
- **Region**: **NYC3** (closest to Philly per STUFF #25's Bus Mode).
- **Redis**: **bundled** in docker-compose (already the case in #104; single-node ephemeral; OK because Sidekiq job loss on a restart is acceptable — feeds re-fetch on the next scheduler tick).
- **TLS**: Caddy on the Droplet mints a Let's Encrypt cert directly via HTTP-01. No CDN / WAF in front for v1.

---

## Out of scope for the sports rollout (intentionally)

Recording the things we discussed and decided NOT to do, so the next reader doesn't think they're oversights:

- **Live in-game commentary / play-by-play streams** — too noisy for an aggregator, better served by ESPN / streaming providers directly.
- **Fantasy / betting integrations** — not the use case.
- **Paid sports APIs (Sportradar, MySportsFeeds)** — free providers cover the user's interests; cost only justified once the user explicitly outgrows free-tier limits.
- **Push notifications for live scores** — non-goal per SPEC.md ("real-time push" is a non-goal). User is welcome to subscribe to the iCal for upcoming-match reminders.
