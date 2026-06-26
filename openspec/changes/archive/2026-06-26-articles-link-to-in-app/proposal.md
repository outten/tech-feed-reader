## Why

Article titles on the triage page and digest page link directly to the publisher's external URL, sending users away from the app before they've even read the summary. The goal is to keep users on the app as long as possible — the in-app reading view (`/article/:uid`) provides the summary, tags, AI insights, and feedback controls that make the app valuable.

## What Changes

- **Triage page** (`views/triage.erb`): Change the article title link from the external publisher URL to the in-app `/article/:uid` page. Add a "Source" link (to the external URL, opening in a new tab) in the meta row. Remove the "Open in app →" link (now redundant).
- **Digest page** (`app/digests.rb`): Change `render_item_html` to link article titles to `/article/:uid` instead of the external URL. Add a "Source" link alongside the feed/date meta. The digest HTML is rendered in-browser at `/digests/:id`, so in-app links are valid and useful.
- **Home page**: Already links article titles to `/article/:uid` throughout — no change needed.
- **Articles list page** (`views/articles.erb`): Already links to `/article/:uid` — no change needed.

## Capabilities

### New Capabilities

### Modified Capabilities
- `article-navigation`: The triage and digest views now route the primary title click to the in-app article page instead of directly to the publisher. Adds a "Source" affordance for users who still want the original.

## Impact

- `views/triage.erb` — title `<a>` href + removal of "Open in app" link + new Source link in meta row
- `app/digests.rb` — `render_item_html`: title href + new Source link in meta row
- No schema changes, no new dependencies
