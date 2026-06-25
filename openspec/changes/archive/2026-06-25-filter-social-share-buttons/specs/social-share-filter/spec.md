## ADDED Requirements

### Requirement: Strip social sharing anchors by share URL
The sanitizer SHALL remove any `<a>` element whose `href` matches a known social-media sharing URL pattern (Twitter/X intent/tweet, Facebook sharer, LinkedIn shareArticle, Reddit submit, Pinterest pin/create, WhatsApp send, Telegram share, email share via mailto with `subject=` or `body=` parameters injected by sharing widgets).

#### Scenario: Twitter share link removed
- **WHEN** article HTML contains `<a href="https://twitter.com/intent/tweet?url=...">Tweet this</a>`
- **THEN** the anchor is removed from the sanitized output

#### Scenario: Facebook share link removed
- **WHEN** article HTML contains `<a href="https://www.facebook.com/sharer/sharer.php?u=...">Share</a>`
- **THEN** the anchor is removed from the sanitized output

#### Scenario: LinkedIn share link removed
- **WHEN** article HTML contains `<a href="https://www.linkedin.com/shareArticle?url=...">Share on LinkedIn</a>`
- **THEN** the anchor is removed from the sanitized output

#### Scenario: Non-sharing social link preserved
- **WHEN** article HTML contains `<a href="https://twitter.com/elonmusk">@elonmusk</a>` (a profile link, not a share URL)
- **THEN** the anchor is preserved in the sanitized output

### Requirement: Strip known sharing widget containers by class
The sanitizer SHALL remove any element whose `class` attribute matches a known social sharing widget class pattern (e.g. `addthis`, `sharethis`, `social-share`, `share-buttons`, `sharedaddy`, `wp-block-social-links`), including all children, regardless of whether child anchors expose share URLs.

#### Scenario: AddThis container removed
- **WHEN** article HTML contains a `<div class="addthis_sharing_toolbox">...</div>`
- **THEN** the entire element and its children are removed

#### Scenario: ShareThis container removed
- **WHEN** article HTML contains a `<div class="sharethis-inline-share-buttons">...</div>`
- **THEN** the entire element and its children are removed

#### Scenario: WordPress Jetpack sharedaddy removed
- **WHEN** article HTML contains a `<div class="sharedaddy sd-sharing-enabled">...</div>`
- **THEN** the entire element and its children are removed

#### Scenario: Unrelated container with "share" in class preserved
- **WHEN** article HTML contains `<div class="market-share-chart">...</div>` (a business chart, not a sharing widget)
- **THEN** the element is preserved (class does not match any known widget pattern)

### Requirement: Backfill existing content
A one-shot operator script SHALL re-sanitize all existing `articles.content_html` rows to remove social sharing markup that was ingested before this filter was added.

#### Scenario: Backfill rewrites rows containing share buttons
- **WHEN** the backfill script is run
- **THEN** any article whose sanitized HTML differs from its stored HTML is updated in the database

#### Scenario: Backfill is idempotent
- **WHEN** the backfill script is run a second time
- **THEN** no rows are written (all stored HTML already matches the sanitized form)

#### Scenario: Backfill supports dry-run mode
- **WHEN** the backfill script is run with `--dry-run`
- **THEN** it reports how many rows would change without writing to the database
