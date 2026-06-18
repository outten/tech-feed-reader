## 1. Benchmark fix + profile (no behavior change)

- [x] 1.1 Update the article-load bench to pick a **content-ful** article (non-empty `top_keywords`), so "uncached article route" reflects reality (the v1.1.0 ~24 ms figure was a body-less article).
- [x] 1.2 Profile `Recommendation.for_article` on a content-ful article: time `top_keywords`, the FTS match (`tsv @@ websearch_to_tsquery`), and `ts_rank` + sort separately; `EXPLAIN (ANALYZE, BUFFERS)` the query. Record whether the cost is the broad OR-match or `ts_rank`.
- [x] 1.3 Record the baseline: real-article route ms (expect ~1.4–2.0 s), `for_article` ms.

## 2. Defer the Related panel off the critical path

- [x] 2.1 Generalize `public/read-next.js` to handle any `[data-fragment-url]` placeholder (sentinel-triggered fetch + swap), or add a sibling; keep the guarded-init + `turbo:load` pattern.
- [x] 2.2 Add `GET /article/:uid/related` that renders just the Related panel (`Recommendation.for_article` + `@feeds_by_id`) as an HTML fragment; empty body when none.
- [x] 2.3 In `views/article.erb`, replace the inline Related panel with a deferred placeholder + sentinel (mirror the Read-next placeholder); move the panel markup into a `_related.erb` partial shared by the route + fragment.
- [x] 2.4 Remove the synchronous `@related = Recommendation.for_article(...)` from `get '/article/:uid'`. (Note: `@feeds_by_id` is still used elsewhere on the page — keep it.)
- [x] 2.5 Spec/test: the article route returns without invoking `for_article`; the fragment returns the panel or empty; page renders when Redis is down.

## 3. Make the deferred Related computation fast

- [x] 3.1 Cache the Related result per `related:v1:{article_id}:{user_id}` via the existing `Cache` (medium TTL); read-through in `for_article` or at the fragment route.
- [x] 3.2 Reduce the cold cost per §1 findings: cap `top_keywords` to fewer terms (narrower OR), and/or pre-limit FTS matches before `ts_rank` (rank only the top-N candidates), preserving the result model.
- [x] 3.3 Add a spec asserting `for_article` returns the same top-N for fixed input (guard the result set across the optimization).
- [x] 3.4 Re-run §1 bench: confirm warm fragment < 200 ms and cold fragment is bounded (no multi-second rank); record the delta.

## 4. Verify & lock in

- [x] 4.1 Confirmed: previously-1.4–2s article now ~10 ms warm / ~241 ms cold (Related deferred).
- [x] 4.2 Guard: related_fragment_spec asserts the article route does NOT call `Recommendation.for_article`; bench adds a content-ful `compute_related` line.
- [x] 4.3 Decided: TWO separate fragments (Related + Read-next), decoupled via the shared lazy-fragment.js — independent failure modes, both load on the same scroll. Not combined.
- [x] 4.4 Full suite green; headless-verified both panels lazy-load on scroll with no reload.
