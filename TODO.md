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

**Status: `not implemented`**

The foundation for everything below. Capture explicit user valence on each article + per feed, store it, expose it cheaply to the ranker.

- [ ] **Schema**: new `feedback` column (or table) keyed on `(article_id, value INT IN {-1, 0, +1}, created_at)`. Per-feed feedback as a separate small table `feed_feedback (feed_id, weight REAL, updated_at)`.
- [ ] **UI on /article/:uid**: thumbs-up / thumbs-down buttons in the actions row alongside Mark read / Bookmark / Archive. Toggle behaviour (clicking 👍 again clears it).
- [ ] **UI on /articles row**: small inline 👍 / 👎 affordances on hover (don't pollute the cleaner row layout we just shipped — appear on hover only).
- [ ] **UI on /feeds**: a "show more / show less from this source" control per feed row that bumps the per-feed weight up or down by a fixed step.
- [ ] **Specs**: round-trip persistence; idempotent toggle; `state_query` doesn't change on read paths (no perf regression).

Cold-start safe: an unset signal is treated as 0, identical to today.

## Relevance-ranked "For You" view on /articles

**Status: `not implemented`**

Adds a sort option that orders unread by a personalised score instead of `published_at DESC`. The default stays chronological so the existing flow doesn't regress.

- [ ] **Score**: blended of (recency decay × per-feed weight × keyword-overlap with the user's positive corpus − keyword-overlap with the negative corpus). Positive corpus = bookmarked + 👍. Negative corpus = 👎 + archived-without-reading.
- [ ] **Implementation**: TF-IDF over `articles_fts` for the overlap terms; precompute the user's term vector at render time (cheap — `articles_fts.bm25` is built in). No background job needed at v1.
- [ ] **Toggle**: `?sort=relevance` on /articles; new state-filter chip "For You" alongside the existing all/unread/bookmarked/archived chips.
- [ ] **Hard cap on negative weight**: a single 👎 shouldn't hide a topic — clamp the demotion so disliked items still surface but lower in the list.
- [ ] **Specs**: empty corpus → identical to chronological; positive-only corpus boosts overlap; negative weight is clamped.

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

**Status: `tests`** — outten/TODO-038, awaiting user approval to commit + open PR

Checkbox per row + a sticky toolbar at the top with "Mark read / Mark unread / Bookmark / Archive" applied to the selected rows. Turns "10 minutes of clicking" into "5 seconds of triage."

- [x] Checkbox per `.news-item` (`opacity 0.3` by default, full opacity on row hover, checked, or when any selection is active).
- [x] Sticky toolbar (`#bulk-toolbar`) appears when ≥1 row is selected; shows the selected count + the bulk actions + a "Clear" button.
- [x] Backend: `POST /api/articles/bulk` taking `{ uids: [], action: "read"|"unread"|"bookmark"|"unbookmark"|"archive"|"unarchive" }`. Returns per-uid `results` so the UI can flag any not-found rows; capped at `BULK_UIDS_MAX = 500` per call; de-duplicates the input list.
- [x] Keyboard: shift-click on a checkbox toggles every row between the last-clicked and this one to the new state (Gmail-style range select).
- [x] Specs: 9 examples in [spec/bulk_articles_route_spec.rb](spec/bulk_articles_route_spec.rb) — round-trip, full action whitelist, 400 paths (unknown action / missing uids / invalid JSON), per-uid result shape with mixed valid/invalid uids, batch cap, de-duplication, and `/articles` toolbar surface.

(👎 deferred — depends on the feedback signal from Phase 3.)

## Skim mode

**Status: `tests`** — outten/TODO-040, awaiting user approval to commit + open PR

A `/articles?view=skim` query that renders title + cached summary only (no body excerpt, no tags, no meta noise) at a larger font, optimised for fast scan-and-triage. Each row still has the row-link to the full article.

- [x] CSS — `.news-list.skim` modifier hides `.news-meta` and `.news-row-badges`, enlarges `.news-headline`, surfaces a 3-line-clamped summary aligned under the headline.
- [x] Toggle in the page header (chip alongside the state filters); preserves `state` and `kind` filters when toggling.
- [x] Summary precedence: LLM > extractive > 240-char content_text excerpt (with ellipsis on truncation). Implemented as `skim_summary_for` helper in [app/main.rb](app/main.rb).
- [x] `SummaryStore.find_for_ids(article_ids)` — batch lookup so the view doesn't N+1 across the page.
- [x] Specs: 13 examples in [spec/skim_mode_spec.rb](spec/skim_mode_spec.rb) covering chip state on/off + filter preservation, `.news-list.skim` modifier, full summary precedence chain (incl. truncation + empty-content fallback), invalid `?view=` value handling, and the new `find_for_ids` lookup.

## Mute filters: keywords, authors, feeds

**Status: `not implemented`**

Per-user negative filters that completely hide matching articles from `/articles` (still in the DB, retrievable via search). Different from per-feed weight: muting is a hard hide, weighting is a soft demotion.

- [ ] Schema: `mute_rules (kind, value, created_at)` where kind ∈ `{keyword, author, feed}`.
- [ ] UI: `/feeds` gets a "Muted" subsection; `/article/:uid` actions include "Mute author" / "Mute this keyword" (with the keyword inferred from the article's top tag or extracted by the server).
- [ ] Backend: `state_query` adds an `AND NOT EXISTS (mute_rule that matches)` clause when mutes are non-empty.
- [ ] Specs: muted articles disappear from listings; still findable via /search; mute rule add/remove round-trips.

## Listened-percent signal for podcasts

**Status: `tests`** — outten/TODO-041, awaiting user approval to commit + open PR

Passive feedback: the global player tracks % consumed. ≥80% = treat like 👍; <10% with >30s of playback (i.e. genuine skip, not a 3-second tap) = treat like 👎. Cheap, doesn't require active interaction.

- [x] `tfr.podcast.listened.<uid>` localStorage key tracks max-currentTime-reached so scrubbing back doesn't undo progress.
- [x] On `ended` ⇒ fetch `/api/podcasts/:uid/feedback` with `signal: 1`. On `pagehide` ⇒ `navigator.sendBeacon` with `signal: 1` (≥80%) or `signal: -1` (<10% AND >30s playback). Once-per-load idempotence so `ended` doesn't double-fire on the subsequent `pagehide`.
- [x] `read_state.passive_feedback` column (Phase 4 migration `007_passive_feedback.sql`); explicit-wins guard lives in `ReadStateStore.mark_passive_feedback` so any future caller (cron, batch import) inherits it.
- [x] Specs: 18 examples in [spec/passive_feedback_spec.rb](spec/passive_feedback_spec.rb) covering store-level explicit-wins (passive can't overwrite explicit; persists when explicit clears), validation, and the full route surface (200 happy path, 200 + applied:false when explicit present, 404 unknown uid, 400 missing/invalid signal, 400 malformed JSON, JSON content-type).

## "Read next" suggestion on /article/:uid

**Status: `not implemented`**

When the user finishes an article (scrolls to bottom OR clicks "Mark read"), surface a "Read next" card with the highest-relevance unread match — leverages the existing Recommendation engine + the new feedback signal.

- [ ] Card slides in below the article body when triggered. Single recommendation, not a panel of five.
- [ ] Click → opens in a new tab (matches the `/articles` row behaviour).
- [ ] If no signal yet, falls back to the existing FTS5 "Related" pick.
- [ ] Specs: trigger conditions; correct fallback when no positive corpus exists.
