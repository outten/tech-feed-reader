## Why

Serendipitous discovery is missing from the app. Users always browse the same feeds in the same order. An "I Feel Lucky" button surfaces random content from across all the user's subscriptions — any topic, any media type — breaking routine and surfacing things that would otherwise be buried.

## What Changes

- **"I Feel Lucky" header icon**: A dice/shuffle icon placed next to the Bus icon in the signed-in header row. Clicking it navigates to `/lucky`.
- **`GET /lucky` route**: Returns up to 50 randomly-sampled articles from the user's subscriptions, across all topics and content types (text, audio, video).
- **`ArticlesStore.random` method**: New query using `ORDER BY RANDOM()` scoped to the current user's subscriptions. Accepts a `limit:` parameter.
- **`views/lucky.erb`**: Renders the random results using the established podcast-card layout with Listen / Watch / Read actions. Each visit re-rolls (no caching).

## Capabilities

### New Capabilities
- `feel-lucky`: `GET /lucky` returns a randomized cross-type article list; a dice icon in the header provides one-click access from anywhere in the app.

### Modified Capabilities
- (none)

## Impact

- `app/articles_store.rb` — add `ArticlesStore.random(user_id, limit:)`
- `app/main.rb` — add `GET /lucky` route
- `views/lucky.erb` — new view (podcast-card list with Listen/Watch/Read actions)
- `views/layout.erb` — add dice icon link to `/lucky` next to the bus icon
- `spec/lucky_spec.rb` — new spec covering 200 response, random item rendering, re-roll on revisit
