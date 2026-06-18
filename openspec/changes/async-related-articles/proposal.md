## Why

The previous change (`speed-up-article-load`, shipped in v1.1.0) deferred the "Read next" card off the article render path and reported the route dropping to ~24 ms. That number was measured against a **degenerate article** whose body produced no keywords — so its Related panel returned `[]` instantly. On a **real, content-ful article the route still takes 1.4–2.0 s**, because `@related = Recommendation.for_article(...)` — the "Related articles" panel — runs **inline and synchronously** and was wrongly assumed cheap (an earlier 0.1 ms reading was the same degenerate case).

Measured against the prod-scale DB (32,610 articles): `for_article` on a content-ful article is **1,300–3,200 ms**. It tokenizes the body into ~8 keywords, OR's them into a `websearch_to_tsquery`, and `ts_rank`s every matching row (the OR of common terms matches thousands of rows) before sorting — a genuinely expensive FTS rank. So the article page still blocks on it, exactly as the user observed for "Read next" before. Deferring Related (and making the deferred work fast) finishes what v1.1.0 started.

## What Changes

- **Defer the Related-articles panel off the article render path**, the same way Read-next was deferred (v1.1.0): the article HTML renders immediately with a placeholder; `public/read-next.js` (or a sibling) fetches the panel from a new fragment endpoint and swaps it in. Target: real-article route back under ~800 ms (ideally ~tens of ms).
- **Make the deferred Related computation itself fast**, so the fragment load isn't a 1.4–2 s spinner. Profile `for_article` (keyword count → OR-query breadth → `ts_rank` cost) and reduce it: bound the candidate set before ranking, cap keyword count, and/or **cache** the per-(article, user) result (it changes only with the article body + the user's subscriptions, both slow-moving).
- **Reconcile the v1.1.0 measurement record** — the article route is not actually ~24 ms for real articles until this lands; update the benchmark to use a content-ful article so the budget is honest and regression-guarded.

## Capabilities

### New Capabilities
- `related-articles-performance`: Defines that the Related panel never blocks the article HTML (deferred or pre-warmed) and that the Related computation itself meets a latency budget at prod-scale corpus.

### Modified Capabilities
<!-- The related `article-page-performance` spec lives in the not-yet-archived
     speed-up-article-load change, so this is captured as a sibling new
     capability rather than a delta. They should be reconciled when both archive. -->

## Impact

- **Code**: `app/main.rb` (`get '/article/:uid'` — drop the inline `@related`; new `GET /article/:uid/related` fragment), `views/article.erb` (Related panel → deferred placeholder), a Related partial (mirror `_read_next.erb`), `public/read-next.js`/sibling (fetch + swap), `app/recommendation.rb` (`for_article` optimization + optional caching via the existing `Cache`).
- **Caching**: reuses the Redis `Cache` (graceful-degradation contract preserved). Possibly a cache-warm hook if we warm it like the For-You ranking.
- **No data model changes** (the `articles.tsv` GIN index already exists); a query rewrite is plausible but no schema change expected.
- **Risk**: low–medium. Deferral changes when the panel appears (same, accepted pattern as Read-next). The `for_article` rewrite touches the Related result set — guard with a test that the same articles are returned for fixed input.
