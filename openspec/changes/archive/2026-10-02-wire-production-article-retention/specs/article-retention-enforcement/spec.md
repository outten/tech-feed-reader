## ADDED Requirements

### Requirement: Production runs the article retention sweep on a schedule
The system SHALL run `Pruner.prune_old` on a recurring schedule in production (via `sidekiq-cron`), not only from the CLI/scheduler path that production doesn't run.

#### Scenario: The daily cron job deletes eligible articles
- **WHEN** the `prune_articles` cron job fires
- **THEN** `Pruner.prune_old` runs and deletes articles older than the configured retention window, subject to the preservation rules below, and logs a structured result (deleted count, kept-bookmarked count, kept-unread count)

### Requirement: Bookmarked articles are never deleted by the automated job
This restates `Pruner`'s existing invariant explicitly as a requirement of the production-facing job — unlike the unread requirement below, this one has NOT changed since the original ship.

#### Scenario: A bookmarked article past the retention window survives
- **WHEN** the `prune_articles` cron job runs and an article is bookmarked, regardless of age or read state
- **THEN** that article is NOT deleted

## MODIFIED Requirements

### Requirement: Unread articles are bounded to a 30-day window, not exempt forever
The scheduled production job SHALL delete unread, non-bookmarked articles once they exceed the retention window (30 days), the same as read articles. This revises the original requirement ("never deletes an unread article") — the original was the correct behavior for the job's first-ever run against an unaudited backlog; it is not the intended steady-state behavior. Bookmarked articles remain the sole unconditional exemption, unchanged.

#### Scenario: Unread articles older than the window are deleted
- **WHEN** the `prune_articles` cron job runs and an article is unread, not bookmarked, and older than 30 days
- **THEN** that article IS deleted

#### Scenario: Unread articles within the window survive
- **WHEN** the `prune_articles` cron job runs and an article is unread, not bookmarked, and within the last 30 days
- **THEN** that article is NOT deleted

#### Scenario: Read or unread status no longer changes the outcome, only bookmarking and age do
- **WHEN** the `prune_articles` cron job runs
- **THEN** an article is deleted if and only if it is not bookmarked AND older than the retention cutoff, regardless of read state
