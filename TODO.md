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

**Status: `tests`** — outten/TODO-043, awaiting user approval to commit + open PR

Adds a sort option that orders unread by a personalised score instead of `published_at DESC`. The default stays chronological so the existing flow doesn't regress.

- [x] **Score**: `recency_decay × per_feed_weight × (1 + α·positive_overlap) × max(NEGATIVE_FLOOR, 1 − β·negative_overlap)`. Positive corpus = bookmarked + 👍 + passive +1. Negative corpus = 👎 + passive -1 + archived-without-reading. Half-life 48h on the recency decay; α=β=0.5 boost/damp; NEGATIVE_FLOOR=0.4 keeps a single 👎 from hiding a topic.
- [x] **Implementation**: pure-compute scorer in [app/recommendation/for_you.rb](app/recommendation/for_you.rb). Pulls top-20 distinctive tokens from each corpus (reusing `Recommendation.top_keywords` + its stopword list); per-candidate overlap is set-intersection on the candidate's title tokens, saturating at OVERLAP_SAT=5 matches. Title-only tokenization on the candidate side keeps the 500-row scoring window fast (titles average ~60 chars vs. content_text averaging ~5KB).
- [x] **Toggle**: `?sort=relevance` on /articles; "For You" chip in the state-filter row alongside the existing chips. Forces state=unread when active (re-ranking already-read articles is rarely useful).
- [x] **Hard cap on negative weight**: NEGATIVE_FLOOR=0.4 clamps `neg_factor`. A single 👎 can't zero out an article — it just sinks ~60%.
- [x] **Specs**: 19 examples in [spec/for_you_spec.rb](spec/for_you_spec.rb) covering empty-corpus → chronological collapse, positive-corpus boost, negative-corpus damp + floor, per-feed-weight multiplication, 48h half-life decay, overlap saturation, corpus selection (incl. archive+read NOT counting as negative — that's the user filing away, not rejecting), score_window orchestration, and the full route + view-surface.

## AI-assisted daily triage

**Status: `not implemented`**

Claude reads today's unread + the user's positive/negative corpus and returns a triage plan: "must-read N, optional N, skip rest" with one-line rationales. Slots into `/digests` as a new flavour or as a separate tab.

- [ ] **Module**: `Triage::Claude` — pulls unread + sample of recent positive/negative corpus + per-feed weights, prompts Claude with a structured-JSON output schema (groups + rationale per article).
- [ ] **Surface**: new `/triage/today` page (or `/digests/triage`) that renders the structured output as three sections.
- [ ] **Cost guard**: cap input tokens (e.g., 30 articles × 1KB excerpt + 20 corpus exemplars × 200 chars). Use `claude-sonnet-4-6` not Opus.
- [ ] **Cron**: optional — extend `make digest` to also produce a triage row, or add `make triage` as a sibling target.
- [ ] **Specs**: Anthropic SDK stubbed; verify the corpus is passed; verify the JSON parsing handles partial responses.

Depends on the feedback signal above to be useful.

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

**Status: `tests`** — outten/TODO-044, awaiting user approval to commit + open PR

When the user scrolls past the bottom of the article body, a "Read next" card slides in with the highest-relevance unread match — leverages the For You ranker + the existing FTS5 fallback.

- [x] Card slides in below the article body when the user scrolls past a sentinel. Single recommendation. CSS-driven slide-in via `.read-next-card-visible` class set by a one-shot IntersectionObserver.
- [x] Click → opens in a new tab (matches the `/articles` row behaviour).
- [x] Fallback chain: For You ranker first; if `Recommendation::ForYou.next_after` returns nil (cold start — empty positive corpus), use the top FTS5 "Related" hit. If neither has anything, the card simply isn't rendered.
- [x] Card label flips between "relevance pick" and "related pick" depending on which path produced the suggestion, so the user can see at a glance whether the ranker is in play yet.
- [x] Specs: 9 examples in [spec/read_next_spec.rb](spec/read_next_spec.rb) covering `next_after` (nil article, empty corpus, top-scoring with non-empty corpus, current-article exclusion) + view-surface (FTS5 fallback path, ranker path, no-card empty case, current-article never linked back, new-tab `target="_blank"`).
