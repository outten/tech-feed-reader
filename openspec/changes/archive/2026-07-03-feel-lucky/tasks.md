## 1. Data layer

- [x] 1.1 Add `ArticlesStore.random(user_id, limit: 50)` — query joining `articles` → `user_feed_subscriptions` with `ORDER BY RANDOM()` and a `LIMIT ?`

## 2. Route

- [x] 2.1 Add `GET /lucky` route in `app/main.rb` (after `/bus`) — calls `ArticlesStore.random`, sets `@page_title`, renders `:lucky`

## 3. View

- [x] 3.1 Create `views/lucky.erb` — podcast-card layout with Listen/Watch/Read actions and a page header; mirrors `feed_show.erb` structure

## 4. Nav icon

- [x] 4.1 Add dice SVG icon link to `/lucky` in `views/layout.erb` next to the bus icon, with `data-turbo-prefetch="false"` and `active` class when on `/lucky`

## 5. Specs

- [x] 5.1 Create `spec/lucky_spec.rb` — tests for 200 response, article titles rendered, Listen/Watch/Read action links
- [x] 5.2 Run `make test` and confirm all specs pass
