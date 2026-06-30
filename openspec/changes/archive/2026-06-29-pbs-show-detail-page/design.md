## Context

The `/pbs` page (`app/main.rb:2384–2396`, `views/pbs.erb`) shows 20 recent PBS articles and a list of subscribed shows in "My PBS" (`@my_feeds`). Currently the show names in "My PBS" are plain text — no link, no way to drill in.

The `/youtube/:feed_id` route (`app/main.rb:2482–2496`) is the direct analogue. It: validates the feed exists, verifies subscription, verifies the URL pattern, then renders a detail view. A `/pbs/:feed_id` route follows the same pattern but validates `feed['topic'] == 'pbs'` instead of a URL pattern check.

## Goals / Non-Goals

**Goals:**
- Show name in "My PBS" section links to `/pbs/:feed_id`.
- `/pbs/:feed_id` route renders all recent articles for that feed (up to 50), newest first.
- Each article item has a context-aware action: "▶ Listen" (audio), "▶ Watch" (YouTube URL), or "Read →" (text).
- All three actions navigate to `/article/:uid` (in-app) — no direct external links for the primary action, consistent with the articles-link-to-in-app change (#106). Exception: "Watch" for YouTube opens externally since YouTube is the consumption surface.
- Back link to `/pbs`.

**Non-Goals:**
- Infinite scroll or pagination (50 articles is enough for a show detail).
- "Browse catalog" section on the detail page — that belongs on `/pbs`.
- Changing the "Recent from PBS" grid on the main `/pbs` page.

## Route Design

```ruby
get '/pbs/:feed_id' do |feed_id|
  @feed = FeedsStore.find(feed_id.to_i)
  halt 404, erb(:article_not_found) unless @feed
  halt 404, erb(:article_not_found) unless FeedsStore.subscribed?(current_user_id, @feed['id'])
  halt 404, erb(:article_not_found) unless @feed['topic'] == 'pbs'

  @page_title = @feed['title'] || 'PBS Show'
  @articles   = ArticlesStore.recent_for_feed(current_user_id, @feed['id'], limit: 50)
  erb :pbs_show
end
```

`ArticlesStore.recent_for_feed` is already defined (used at `/youtube/:feed_id`). Check the exact method name — it may be `for_feed` or `recent_for_feed`; verify in articles_store.rb before implementing.

## View Design (`views/pbs_show.erb`)

```
[Back to PBS]            ← link to /pbs
[Show image if present]  [Show title]  [show description/url]

[N episodes]

<ul class="podcast-episodes">
  <li class="podcast-card [read] [has-image]">
    [thumbnail if image_url]
    [show title · relative_time · duration]
    [episode title → /article/:uid]
    [excerpt (240 chars)]
    [▶ Listen | ▶ Watch (new tab) | Read →]
  </li>
  ...
</ul>

[Empty state if no articles yet]
```

**Action logic per article:**
- `audio_url` present → `<a href="/article/:uid">▶ Listen</a>` (btn-primary)
- `url` matches `youtube.com` or `youtu.be` → `<a href="[external url]" target="_blank">▶ Watch</a>` (btn-primary)
- Otherwise → `<a href="/article/:uid">Read →</a>` (btn-secondary)

The card structure reuses the exact `.podcast-card` CSS already used on `/pbs`.

## `views/pbs.erb` Change

In the "My PBS" section, wrap the show title in a link:

```erb
<%# Before: %>
<span class="catalog-title"><%= h(feed['title'] || feed['url']) %></span>

<%# After: %>
<a class="catalog-title" href="/pbs/<%= feed['id'] %>"><%= h(feed['title'] || feed['url']) %></a>
```
