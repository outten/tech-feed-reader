## 1. Nav

- [x] 1.1 Add "Feeds" top-level nav link in `views/layout.erb` (active on `/feeds` and `/feeds/*`)

## 2. Feed list links

- [x] 2.1 In `views/feeds.erb`, make each feed title in the "My Subscriptions" section a link to `/feeds/<feed_id>`

## 3. Per-feed route and view

- [x] 3.1 Add `GET /feeds/:feed_id` route in `app/main.rb` (after fixed `/feeds` routes; guard: subscribed? only; load 50 articles via `ArticlesStore.for_feed`)
- [x] 3.2 Create `views/feed_show.erb` — per-feed content list with podcast-card layout, Listen/Watch/Read actions, back link to `/feeds`

## 4. Specs

- [x] 4.1 Create `spec/feed_show_spec.rb` — tests for 200/404 and Listen/Watch/Read action rendering
- [x] 4.2 Run `make test` and confirm all specs pass
