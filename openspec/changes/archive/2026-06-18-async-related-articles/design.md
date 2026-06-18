## Context

`get '/article/:uid'` still computes `@related = Recommendation.for_article(current_user_id, @article, limit: 5)` inline. `for_article` (app/recommendation.rb):
1. `top_keywords(content_text)` → ~8 distinctive body tokens.
2. OR's them into `websearch_to_tsquery('english', 'k1 OR k2 …')`.
3. `SELECT a.*, ts_rank(a.tsv, …) … WHERE a.tsv @@ … AND a.id != ? AND EXISTS(subscription) ORDER BY rank LIMIT 5`.

The OR of 8 common terms matches thousands of the 32k articles, and `ts_rank` is evaluated for every match before the top-5 sort. Measured cost on content-ful articles: **1.3–3.2 s** (route wall-clock 1.4–2.0 s). The v1.1.0 deferral of Read-next did **not** cover this; the article page only looked fast because it was verified on a body-less article where `for_article` short-circuits to `[]`.

This is the same shape as the Read-next problem and the same toolkit applies: defer it off the render path, and make the deferred work cheap (bound/cache). Constraints unchanged: cache-only render, Redis `Cache` must degrade gracefully, single small managed Postgres, `articles.tsv` GIN index exists.

## Goals / Non-Goals

**Goals:**
- Real-article `/article/:uid` HTML renders well under 800 ms (target ~tens of ms) at 32k-article scale — finishing the v1.1.0 intent.
- The Related panel never blocks article render.
- The Related computation itself is fast (so the deferred fragment isn't a multi-second spinner): bound and/or cache `for_article`.
- Honest, regression-guarded benchmark using a content-ful article.

**Non-Goals:**
- Changing what "Related" means (the FTS keyword-similarity model stays); only its cost and when it runs.
- Reworking the Read-next deferral (already shipped) beyond possibly sharing its fetch JS.
- Schema changes (the GIN index already exists).

## Decisions

**1. Defer Related to a fragment, mirroring Read-next.**
New `GET /article/:uid/related` renders just the panel; the page ships a placeholder that the client swaps in. The Related panel sits just above the Read-next sentinel near the article bottom, so the same on-scroll lazy-load applies. *Reuse vs. new JS:* extend the existing `read-next.js` (generalize to any `[data-fragment-url]` placeholder) rather than add a parallel script — Related and Read-next are adjacent and identical in mechanism. *Alternative:* a single combined "more to read" fragment that returns both Related + Read-next in one request — tempting (one round-trip), but keeps two independent failure modes coupled; decide in tasks after the JS is generalized.

**2. Make `for_article` cheap — cache first, optimize if still slow.**
The result depends only on the article body (immutable post-import) and the user's subscription set (slow-moving) → highly cacheable. Cache the rendered id-list under `related:v1:{article_id}:{user_id}` with a medium TTL, like the For-You ranking. A cold miss still pays the FTS cost, so also profile and reduce it: cap `top_keywords` to fewer terms (narrower OR → fewer matches to rank), and/or pre-limit candidates before `ts_rank` (rank only the top-N FTS matches, not all). *Alternative:* drop `ts_rank` for a cheaper ordering — rejected unless profiling shows ranking is the dominant term and quality is unaffected.

**3. Optionally warm it.** If we want the deferred fragment instant, the existing `ForYouCacheWarmWorker` pattern could warm recent articles' Related too — but Related is per-article (unbounded set), so warming is less natural than for the per-user ranking. Default: cache-on-demand + a cheaper query; warming only if needed.

**4. Fix the benchmark.** `bench_hotpaths.rb` / the article-load bench must use a content-ful article so "uncached article route" reflects reality. The prior change's ~24 ms figure was degenerate.

## Risks / Trade-offs

- **[Deferral changes when Related appears]** → same accepted pattern as Read-next; lightweight placeholder, loads on scroll.
- **[Cache staleness]** → Related changes only as new articles import; a medium TTL (or bust on import) keeps it fresh enough. Per-(article,user) keys can multiply — bound TTL and rely on Redis eviction.
- **[`for_article` rewrite changes results]** → guard with a spec asserting the same top-N for fixed input; keep the FTS model.
- **[Redis down]** → `Cache` degrades to compute; with the query also optimized, a cold path is tolerable and still off the critical render path.
- **[Two fragments = two requests]** → consider the combined endpoint; measure before committing.

## Migration Plan

Independently-shippable, measured per step (deploy-gated):
1. **Bench fix + profile** `for_article` on a content-ful article (confirm keyword/ts_rank cost split). No behavior change.
2. **Defer Related** (generalize `read-next.js`, new fragment endpoint, placeholder) — the immediate render win.
3. **Cache + optimize `for_article`** so the deferred load is fast — measured before/after.
4. (Optional) combine Related + Read-next into one fragment, or warm the cache, if warranted.

Rollback: each step is its own commit/PR; deferral + caching are additive and revertible; no schema change.

## Open Questions

- One combined "more to read" fragment (Related + Read-next) vs. two? Decide after generalizing the fetch JS.
- Cache invalidation: TTL-only vs. bust `related:v1:{article_id}:*` when that article's feed imports new items (affects everyone's Related for *other* articles, not this one — so TTL is probably enough).
- Is the dominant cost the broad OR-match or `ts_rank`? Step 1 profiling decides whether capping keywords or pre-limiting candidates is the lever.
