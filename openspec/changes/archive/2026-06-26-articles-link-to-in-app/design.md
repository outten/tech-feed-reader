## Context

Two views currently send users to the publisher on title click:

**Triage page** (`views/triage.erb` ~line 123): the title `<a>` points to `article['url']` with `target="_blank"`. A separate "Open in app →" link at the bottom of the meta row points to `/article/:uid`. The fix swaps these: title → `/article/:uid` (no new tab), Source → `article['url']` (new tab), remove "Open in app".

**Digest page** (`app/digests.rb` `render_item_html`): the title anchor is built inline: `%(<a href="#{url}" target="_blank" rel="noopener">#{title}</a>)`. The digest `html_body` is rendered server-side at build time and stored in the `digests` table; it is rendered in-browser at `/digests/:id`. Since the app runs at a fixed origin, `/article/:uid` is a valid relative path.

The home page and articles list already use in-app links — no changes there.

## Goals / Non-Goals

**Goals:**
- Title click on triage and digest goes to `/article/:uid` (no new tab — staying in the app).
- External "Source" link retained so users can still reach the original publisher.
- "Open in app" removed from triage (redundant once title links in-app).

**Non-Goals:**
- Changing the articles list, sports pages, or any other view.
- Changing what happens on the `/article/:uid` page itself.
- Tracking or analytics on source link clicks.

## Decisions

**Triage: swap title href, keep Source in meta row**
The meta row already has feed filter link · date · author · audio badge · "Open in app". Replace "Open in app" with a "Source →" link pointing to `article['url']` (same `target="_blank" rel="noopener noreferrer"`). The title `<a>` keeps `title=` attribute updated to reflect the in-app destination.

**Digest: `/article/:uid` is a relative path — safe to use**
The digest `html_body` is rendered in-browser; relative paths work. The `uid` is available on each `row` passed to `render_item_html` (`row['uid']`). Add a Source link inline after the feed · date meta.

**No `target="_blank"` on in-app title links**
External links open new tabs to avoid losing context. In-app navigation should stay in the same tab — standard SPA/reader behavior.

## Risks / Trade-offs

- **Digest emails**: if digest HTML is ever emailed, `/article/:uid` relative links break in email clients. Currently digests are only rendered in-browser — but if email is added later, the digest builder will need to use absolute URLs. The design doc should be updated at that point.
- **Triage read-state**: the triage card already marks articles read when "Open in app" is clicked (via the article page). Changing the title to link in-app preserves that behavior.

## Migration Plan

Two-file edit: `views/triage.erb` and `app/digests.rb`. No data migration. Deploy and done.
