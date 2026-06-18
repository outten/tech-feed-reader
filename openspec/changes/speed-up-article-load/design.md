## Context

`get '/article/:uid'` (app/main.rb) renders the reader page from ~9 synchronous calls. A component bench against the prod-scale dev DB (32,610 articles, user 1) isolated the cost:

| Call | Cold time |
|---|---|
| `ArticlesStore.find_by_uid` | ~20 ms |
| `Recommendation.for_article` (FTS "Related") | ~0.1 ms |
| **`Recommendation::ForYou.next_after`** (the "Read next" card) | **~4,012 ms** |

`next_after` calls `score_window(state: :unread, limit: 25, offset: 0)`, which on a cache miss runs `compute_ranking`: two corpus SQL queries (`positive_corpus` / `negative_corpus`, `CORPUS_LIMIT=50` rows each, pulling `content_text`), one candidate fetch (`ArticlesStore.recent`, `CANDIDATE_WINDOW=500` unread rows), then a Ruby loop that tokenizes each candidate's title (`Recommendation.top_keywords`) and scores it. The result is cached as a sorted id-list for `RANKING_TTL=300 s`, so **warm loads are fast and only a cold cache pays the ~4 s** — which is the user-reported "uncached" case. The same cold computation also affects the home page and `/articles?sort=relevance`.

Constraints: cache-only render contract (no network I/O in the request); Redis `Cache` must degrade gracefully (a missing cache must still render fast — so "just cache harder" is not sufficient on its own); single managed Postgres (`db-s-1vcpu-1gb`); Sidekiq available for background work.

## Goals / Non-Goals

**Goals:**
- Uncached `/article/:uid` HTML renders in **< 800 ms** server-side at 32k-article scale (from ~5 s).
- The personalized "Read next" card never blocks the article HTML.
- Root-cause *which* part of `compute_ranking` costs ~4 s and fix it, so the home page and relevance sort benefit too.
- Establish a repeatable benchmark + budget to prevent regression.

**Non-Goals:**
- Changing the For-You ranking *algorithm* / relevance quality (only its cost and when it runs).
- A general caching framework rewrite — reuse the existing `Cache`.
- Front-end framework changes; the client-side audit is measure-first and fixes only confirmed serial/blocking work on the article page.

## Decisions

**1. Profile `compute_ranking` before optimizing (no speculative indexes).**
Add a breakdown bench (corpus queries vs. candidate fetch vs. Ruby scoring) and `EXPLAIN (ANALYZE, BUFFERS)` the candidate/corpus SQL against the real corpus. The #98 work already established that guessing at indexes is wrong here — fix the measured cost. *Alternatives:* blindly add the "missing indexes" earlier agents suggested → rejected; the hot query may be Ruby-bound, not IO-bound.

**2. Make "Read next" non-blocking — deferred fragment (primary), with cheap-compute as a fallback.**
Render the article HTML immediately with a placeholder Read-next card, then load it via a lazy `turbo-frame` / small AJAX fetch to a new `GET /article/:uid/read-next` endpoint (mirrors the existing `_stock_news.erb` deferred-fragment pattern from #96/#97). The 4 s (until optimized) then happens off the critical path and the page paints fast regardless of cache state.
*Alternatives considered:*
- *Make `next_after` cheap by reusing the list ranking* — `next_after` recomputes its own 25-row window; it could instead read the already-cached `ranked_ids` the `/articles` list builds. Good, but only helps if that cache is warm; combine with (3).
- *Drop Read-next entirely* — rejected, it's a real feature.

**3. Warm the ranking cache in the background.**
A Sidekiq job (cron, every few minutes / before `RANKING_TTL` lapses) precomputes `ranked_ids` for recently-active users, so the article page and home page hit a warm cache. This turns the deferred fragment's first load fast too. *Alternative:* increase TTL — rejected, staleness vs. recency-decay tradeoff, and it doesn't help the truly-cold first computation.

**4. Optimize the computation itself based on (1).** Likely levers, to be confirmed by profiling: bound/shrink `CANDIDATE_WINDOW`, avoid pulling `content_text` when only keywords are needed, memoize `title_tokens`, or add a covering index for the unread-candidate scan. Each gated on a before/after measurement.

**5. Client-side audit is measure-first.** Capture a real authenticated article-page network waterfall (the #98 harness). Only fix confirmed issues (e.g. serial external images, render-blocking head scripts already addressed by self-hosting Turbo in v1.0.6).

## Risks / Trade-offs

- **[Deferring Read-next changes UX timing]** → the card appears a beat after the page; acceptable and standard (same pattern as stock-news). Show a lightweight skeleton.
- **[Cache-warming job adds load / more DB connections]** → keep it cheap, batch active users, respect the `db-s-1vcpu-1gb` connection budget; it replaces work already done on-request, net-neutral or better.
- **[Index on the hot recommendation path]** → measure before/after with `EXPLAIN ANALYZE`; ship only if it demonstrably helps and doesn't bloat writes.
- **[Optimizing changes ranking output]** → guard with the existing For-You specs; assert the ordering is unchanged for fixed inputs.
- **[Can't fully reproduce 5 s locally for client-side]** → the server 4 s is reproduced and is the dominant term; client work is scoped to what the waterfall shows.

## Migration Plan

Ship in independently-revertible phases, each measured locally then in prod (per the established deploy gate):
1. **Profile + bench** (`scripts/bench_hotpaths.rb` extension) — no behavior change.
2. **Defer the Read-next card** (route + view + new fragment endpoint) — biggest user-felt win, low risk, instantly unblocks page paint.
3. **Optimize `compute_ranking`** per profiling (index and/or bounded work) — measured before/after.
4. **Cache-warming job** — makes the deferred fragment fast too.
5. **Client-side audit + fixes** if the waterfall shows real serial/blocking work.

Rollback: each phase is a separate commit/PR; deferral and cache-warming are additive and can be reverted without data changes; an index migration is reversible.

## Open Questions

- Should `next_after` *reuse* the `/articles` list ranking cache (shared key) rather than its own `limit:25` window? (Cheaper, but couples the two; decide after profiling shows whether the recompute or the deferral is sufficient.)
- Cache-warm cadence and the definition of "active user" (last-seen window) — tune to the connection budget.
- Is the ~4 s dominated by the `CANDIDATE_WINDOW=500` fetch+score or the corpus `content_text` tokenization? Phase 1 answers this and may collapse later phases.
