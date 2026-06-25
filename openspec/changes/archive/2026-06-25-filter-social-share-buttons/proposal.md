## Why

Social media sharing buttons embedded in ingested article HTML don't work (they reference the original publisher's page, not the reader's context) and frequently render as broken icons, orphaned text, or bare share-URL links — visual noise that degrades the reading experience.

## What Changes

- Add a `SocialShareScrubber` Loofah scrubber to `app/sanitizer.rb` that strips social sharing widgets from article HTML at ingest time.
- Wire the new scrubber into the `sanitize_html` pipeline so all newly ingested content is clean.
- Add a one-shot backfill script (`scripts/strip_social_share.rb`) to re-sanitize existing `articles.content_html` rows — same pattern as `scripts/fix_article_links.rb`.

## Capabilities

### New Capabilities
- `social-share-filter`: A content scrubber that detects and removes social media sharing widgets (buttons, links, wrapping containers) from ingested article HTML before it is stored and rendered.

### Modified Capabilities

## Impact

- `app/sanitizer.rb` — new `SocialShareScrubber` class, wired into `sanitize_html`
- `spec/sanitizer_spec.rb` — new unit tests for the scrubber
- `scripts/strip_social_share.rb` — one-shot backfill script
- `articles.content_html` — existing rows rewritten by the backfill (idempotent; re-running is safe)
- No schema changes, no new dependencies
