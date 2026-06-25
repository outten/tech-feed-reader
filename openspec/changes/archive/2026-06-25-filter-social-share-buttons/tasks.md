## 1. Find a live example

- [x] 1.1 Query the production DB (or local DB) for an article whose `content_html` contains a known share-URL pattern (e.g. `twitter.com/intent/tweet`, `facebook.com/sharer`, `addthis`) and note its `uid` for before/after verification

## 2. Implement SocialShareScrubber

- [x] 2.1 Add `SocialShareScrubber` class to `app/sanitizer.rb`: remove `<a>` elements whose `href` matches a share-URL pattern (Twitter, Facebook, LinkedIn, Reddit, Pinterest, WhatsApp, Telegram)
- [x] 2.2 Extend the scrubber to also remove elements whose `class` matches known sharing widget patterns (addthis, sharethis, sharedaddy, social-share, share-buttons, wp-block-social-links, etc.)
- [x] 2.3 Wire `SocialShareScrubber` into `Sanitizer.sanitize_html` after the existing `:prune` pass

## 3. Show before/after on the live example

- [x] 3.1 Load the article found in 1.1 and print the raw `content_html` excerpt containing the share buttons
- [x] 3.2 Run it through `Sanitizer.sanitize_html` with the new scrubber and print the cleaned excerpt — confirm share buttons are gone

## 4. Tests

- [x] 4.1 Add unit tests in `spec/sanitizer_spec.rb` covering: Twitter share link removed, Facebook share link removed, LinkedIn share link removed, profile link preserved, AddThis container removed, ShareThis container removed, sharedaddy container removed, unrelated "share" class preserved

## 5. Backfill script

- [x] 5.1 Create `scripts/strip_social_share.rb` following the `ArticleLinkScrubber` pattern: iterate all articles, re-run `sanitize_html`, write rows where content changed, support `--dry-run` and `--limit N` flags
- [x] 5.2 Add a `make strip-social-share` target to the Makefile
