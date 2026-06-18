## ADDED Requirements

### Requirement: Related panel never blocks the article HTML
The "Related articles" panel SHALL NOT be computed synchronously on the critical render path of `GET /article/:uid`. The article HTML SHALL render without waiting on the Related FTS query; the panel MAY be deferred and loaded after first paint, or served pre-computed.

#### Scenario: Content-ful article renders fast
- **WHEN** a signed-in user opens an article whose body yields keywords (a real, non-degenerate article) at prod-scale corpus (≥ 30,000 articles)
- **THEN** the article HTML is returned in under 800 ms
- **AND** the response does not block on the Related `ts_rank` query

#### Scenario: Related loads after render
- **WHEN** the Related panel is deferred
- **THEN** the article page renders immediately with a placeholder
- **AND** the related items are filled in via a follow-up request
- **AND** if there are no related items the placeholder resolves to empty without error

### Requirement: Related computation meets a latency budget
The deferred Related computation (`Recommendation.for_article`) SHALL be fast enough that the deferred fragment is not a multi-second wait — via caching of the per-(article, user) result and/or bounding the FTS work — while preserving the keyword-similarity result set.

#### Scenario: Warm Related fragment
- **WHEN** the Related result for an (article, user) is cached
- **THEN** the fragment responds in well under 200 ms

#### Scenario: Cold Related fragment is bounded
- **WHEN** the Related result is not cached
- **THEN** it is computed and returned without the multi-second cost of ranking every FTS match
- **AND** the returned articles match the keyword-similarity model (same top-N for fixed input)

#### Scenario: Cache degradation
- **WHEN** the Redis cache is unavailable
- **THEN** the Related fragment still returns (computed fresh) without erroring the page

### Requirement: Article-load benchmark reflects a real article
The article-load benchmark SHALL exercise a content-ful article (one whose body yields keywords) so the measured route time is not the degenerate `for_article == []` case.

#### Scenario: Benchmark uses a non-degenerate article
- **WHEN** the article-load benchmark runs
- **THEN** it selects an article with a non-empty keyword set
- **AND** the reported uncached route time reflects the Related cost (before the change) and the budget (after)
