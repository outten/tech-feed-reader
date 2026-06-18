## ADDED Requirements

### Requirement: Uncached article page renders within budget
The article reader page (`GET /article/:uid`) SHALL return its HTML in under 800 ms (server-side, measured at the route) at production-scale corpus size (≥ 30,000 articles), regardless of whether the per-user For-You ranking cache is warm or cold. No single synchronous call in the route SHALL exceed the page budget.

#### Scenario: Cold ranking cache
- **WHEN** a signed-in user opens an article and their For-You ranking cache is empty or expired
- **THEN** the article HTML is returned in under 800 ms
- **AND** the response is not blocked waiting on the full ranking computation

#### Scenario: Warm ranking cache
- **WHEN** the user's ranking cache is warm
- **THEN** the article HTML is returned in under 800 ms (unchanged-fast behavior preserved)

### Requirement: Personalized "Read next" never blocks the article HTML
The personalized "Read next" suggestion SHALL be produced without delaying first paint of the article. It MAY be deferred and loaded after the page renders, or served from a pre-warmed cache, but its computation SHALL NOT run synchronously on the critical render path of the article route.

#### Scenario: Read-next deferred while computing
- **WHEN** the "Read next" suggestion is not yet available for the user
- **THEN** the article page renders immediately with a placeholder
- **AND** the suggestion is filled in via a follow-up request once computed
- **AND** if the suggestion cannot be produced, the page degrades to the existing FTS "Related" fallback without error

#### Scenario: Cache degradation still fast
- **WHEN** the Redis cache is unavailable
- **THEN** the article page still renders within budget (the page does not block on a from-scratch ranking)

### Requirement: For-You ranking stays warm for active users
The system SHALL keep the For-You ranking cache warm for recently-active users so the article page, home page, and relevance sort hit a warm cache in normal operation, without exceeding the managed Postgres connection budget.

#### Scenario: Background warming
- **WHEN** a recently-active user's ranking cache is near expiry
- **THEN** a background job recomputes and refreshes it before the next request needs it

### Requirement: Article-load performance is benchmarked and regression-guarded
The repository SHALL provide a repeatable benchmark for the uncached article path (the ranking computation and the article route) so the improvement is measurable and regressions are detectable.

#### Scenario: Benchmark reports component timings
- **WHEN** the article-load benchmark is run against a populated database
- **THEN** it reports the per-component timings (candidate fetch, corpus queries, scoring, total)
- **AND** the measured uncached total is under the established budget after the change
