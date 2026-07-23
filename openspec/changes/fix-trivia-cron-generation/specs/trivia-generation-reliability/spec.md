## ADDED Requirements

### Requirement: Trivia source selection is resilient to low-content articles
`TriviaStore.fetch_source_articles` SHALL exclude articles whose `content_text` is too short to plausibly support a meaningful trivia question, regardless of which feed produced them or what `published_at` they carry, so a single low-substance feed cannot starve daily trivia generation of usable material.

#### Scenario: A feed with near-empty content and a recent-looking published_at is excluded
- **WHEN** the last 24 hours contain articles whose `content_text` is only a few words (e.g. comic captions) but whose `published_at` sorts them ahead of genuine news
- **THEN** those articles are excluded from the top-20 source-article selection, and genuine substantive news articles are selected instead

#### Scenario: A normal day still selects the most recent substantive articles
- **WHEN** the last 24 hours contain the usual abundance of real, substantive news articles
- **THEN** `fetch_source_articles` returns up to 20 of the most recent ones, unaffected by the content-length filter

### Requirement: A failed or skipped generation is observable same-day
When `TriviaStore.ensure_today!` fails to produce a quiz (whether due to insufficient source material, a Claude parsing failure, or unavailability), the operator SHALL be notified the same day, since this failure mode completes the Sidekiq job without an exception and therefore never reaches the existing dead-job alert.

#### Scenario: Skipped generation pages the operator
- **WHEN** `GenerateTriviaWorker#perform` calls `ensure_today!` and it returns `nil`
- **THEN** an alert is pushed via `Notifier.push` (same mechanism as the dead-job alert), in addition to the existing `AppLogger.warn('generate_trivia_skipped', ...)` log line
