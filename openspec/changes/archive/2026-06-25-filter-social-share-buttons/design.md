## Context

Article HTML is ingested from RSS feeds, sanitized via `Sanitizer.sanitize_html` (Loofah `:prune` whitelist + custom scrubbers), and stored in `articles.content_html`. Publishers routinely embed social sharing widgets — AddThis, ShareThis, Twitter/X share buttons, Facebook Like buttons, etc. — as anchors or containers inside article bodies. Because these widgets reference the original page URL and depend on third-party JS that we never load, they render as broken links, bare text, or orphaned icons in the reader view.

The sanitizer already has the right shape: `LinkAbsolutizer` and `ExternalLinkScrubber` are Loofah scrubbers chained in `sanitize_html`. Adding another scrubber in the same pattern is the natural fit.

## Goals / Non-Goals

**Goals:**
- Strip social sharing anchors and their wrapper elements before content is stored.
- Apply at ingest time (the `sanitize_html` call) so all future content is clean.
- Provide a one-shot backfill script to clean existing rows.
- Zero false positives on legitimate content (article body links to social profiles, inline mentions of Twitter, etc.).

**Non-Goals:**
- Removing social sharing buttons from the publisher's original page — we only control our stored copy.
- Stripping social embeds (quoted tweets, YouTube iframes) — those are a separate concern.
- Removing generic ad or tracking pixels (out of scope for this change).

## Decisions

**Detection strategy: share-URL href patterns (primary) + CSS class patterns (secondary)**

Social sharing buttons are reliably identified by their `href`: `twitter.com/intent/tweet`, `facebook.com/sharer`, `linkedin.com/shareArticle`, `reddit.com/submit`, `pinterest.com/pin/create`, etc. These URLs exist for no purpose other than sharing and never appear in genuine editorial content.

CSS class patterns (`addthis`, `sharethis`, `share-buttons`, `social-share`, etc.) catch widget containers whose inner anchors may not expose share URLs (e.g. AddThis loads its content via JS). A container is removed only when its class clearly identifies it as a share widget — we never remove a container based solely on generic class names like `social`.

Alternative considered: element-level heuristics (count child anchors with share-URL hrefs, remove parent). Rejected — too fragile, could remove legitimate navigation lists.

**Scrub the anchor AND bubble up to remove the container when it's share-only**

If an `<a>` has a share URL, remove it. If its parent element has only share-children left (or is itself a known share widget class), remove the parent too. This avoids leaving empty `<div>` wrappers in the HTML.

Alternative considered: remove only the anchor, leave the container. Simpler but leaves orphaned markup.

**Backfill pattern: mirror `ArticleLinkScrubber`**

The backfill script (`scripts/strip_social_share.rb`) re-runs `sanitize_html` over rows where `content_scrubbed = TRUE` (all previously processed rows). Unlike `ArticleLinkScrubber` which used the `content_scrubbed = FALSE` flag as a work queue, the social-share backfill must touch already-scrubbed rows. It does NOT reset the `content_scrubbed` flag — that flag tracks link absolutization, not social share state.

## Risks / Trade-offs

- **False positives on share-URL editorial links** — e.g. an article that says "click here to tweet this quote" with a real `twitter.com/intent/tweet` link. These are rare and the user is right that they don't work in our context. Acceptable to remove them.
- **Class-pattern brittleness** — publishers invent new widget class names. The class list can be extended over time; misses are low-harm (broken widget stays visible until next pattern addition). → Mitigation: favor specific multi-word class names (`addthis_sharing_toolbox`) over short ones (`share`).
- **Backfill scope** — touching all `articles.content_html` rows at once could be a large write. → Mitigation: script processes in batches and can be run with `--limit N` for a staged rollout.

## Migration Plan

1. Add `SocialShareScrubber` to `app/sanitizer.rb`, wire into `sanitize_html`.
2. Run `spec/sanitizer_spec.rb` — all new + existing tests green.
3. Find a live article with sharing buttons; verify before/after with the scrubber.
4. Deploy (new content clean from this point on).
5. Run `scripts/strip_social_share.rb` on production to backfill existing rows.

Rollback: remove the scrubber from the `sanitize_html` chain; re-run backfill is not needed (original HTML is not stored — it was already sanitized on ingest).
