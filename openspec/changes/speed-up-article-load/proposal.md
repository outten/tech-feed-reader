## Why

Loading an **uncached** article page (`/article/:uid`) takes 5+ seconds. A measurement against the production-scale dev DB (32,610 articles) pinpoints the cause: the route blocks on `Recommendation::ForYou.next_after` — the "Read next" suggestion — which recomputes the full For-You ranking when the per-user ranking cache is cold. That single call measured **~4,012 ms**, while every other piece of the route is fast (`find_by_uid` ~20 ms, `Recommendation.for_article` ~0.1 ms). The expensive ranking runs **synchronously in the request**, so the whole page waits on it before first paint. Warm loads are fast (the 5-minute cache hides it), which is why this only bites on a cold cache — exactly the "uncached" case the user reports.

## What Changes

- **Stop blocking page render on the For-You ranking.** The "Read next" card must not hold up the article HTML. Either compute it cheaply, serve it from an already-warm cache, or load it after the page paints (deferred/async). Target: uncached article HTML returns in well under 1 s.
- **Investigate and reduce the cost of the ranking computation itself** (`ForYou.compute_ranking`) at 32k-article scale — profile its three parts (the `CANDIDATE_WINDOW=500` candidate fetch, the positive/negative corpus queries, and the Ruby tokenize-and-score loop) to find where the ~4 s goes. Add a covering index if the candidate/corpus SQL is the cost (the user's "possibly not indexed well" hunch); bound or restructure the Ruby work if that is the cost.
- **Keep the per-user ranking cache warm** so the article page (and `/articles?sort=relevance`, the home page) never pays a cold-cache penalty — e.g. a background Sidekiq job that precomputes the ranking for active users before the TTL lapses, and/or making `next_after` reuse the list's already-computed ranking instead of recomputing its own 25-item window.
- **Audit the client side** for the secondary, user-noted symptom — resources that load serially instead of in parallel and synchronous front-end steps that could overlap (carried over from the #98 investigation: external article-body images, Turbo prefetch behavior). Scope: measure and fix only what a real article page actually does.
- **Establish a measurable performance budget** for the uncached article page so the fix is verifiable and protected against regression.

## Capabilities

### New Capabilities
- `article-page-performance`: Defines the latency budget and non-blocking behavior for rendering `/article/:uid` — cold-cache server render time, the requirement that personalized "Read next" never blocks the article HTML, and how the For-You ranking cache stays warm.

### Modified Capabilities
<!-- No existing specs in openspec/specs/; the recommendation/article behavior is not yet spec'd, so this is captured as a new capability rather than a delta. -->

## Impact

- **Code**: `app/recommendation/for_you.rb` (`next_after`, `compute_ranking`, `ranked_ids`), `app/main.rb` (`get '/article/:uid'` route + a possible deferred-fragment endpoint), `views/article.erb` (Read-next card, possibly a lazy turbo-frame), `app/articles_store.rb` (`recent` candidate query), possibly a new `db/migrations/*.sql` index and a new `app/workers/*` cache-warming job.
- **Caching**: relies on the existing Redis `Cache` (graceful-degradation contract preserved — a cold/absent cache must still render fast, which is the whole point).
- **No data model changes** beyond a possible index. No API/contract changes for end users; the Read-next card may render a moment after the page if deferred.
- **Risk**: low–medium. Deferring/​reusing the ranking changes when the Read-next card appears; the candidate query/index change touches the hot recommendation path and must be measured before/after.
