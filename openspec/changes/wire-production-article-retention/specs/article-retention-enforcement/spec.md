## ADDED Requirements

### Requirement: Production runs the article retention sweep on a schedule
The system SHALL run `Pruner.prune_old` on a recurring schedule in production (via `sidekiq-cron`), not only from the CLI/scheduler path that production doesn't run.

#### Scenario: The daily cron job deletes eligible articles
- **WHEN** the `prune_articles` cron job fires
- **THEN** `Pruner.prune_old` runs and deletes articles older than the configured retention window, subject to the preservation rules below, and logs a structured result (deleted count, kept-bookmarked count, kept-unread count)

### Requirement: The automated retention job never deletes an unread article
Regardless of environment configuration, the scheduled production job SHALL preserve every unread article.

#### Scenario: Unread articles survive the automated sweep
- **WHEN** the `prune_articles` cron job runs and an article is unread and not bookmarked, even if older than the retention cutoff
- **THEN** that article is NOT deleted

#### Scenario: Only read, non-bookmarked, expired articles are deleted
- **WHEN** the `prune_articles` cron job runs
- **THEN** only articles that are both read AND not bookmarked AND older than the retention cutoff are deleted

### Requirement: Bookmarked articles are never deleted by the automated job
This restates `Pruner`'s existing invariant explicitly as a requirement of the production-facing job, since it's the second half of what makes running this unattended safe.

#### Scenario: A bookmarked article past the retention window survives
- **WHEN** the `prune_articles` cron job runs and an article is bookmarked, regardless of age or read state
- **THEN** that article is NOT deleted
