## 1. Triage page

- [x] 1.1 In `views/triage.erb`, change the article title `<a>` href from `h(article['url'])` to `/article/<%= article['uid'] %>` and remove `target="_blank"` and `rel="noopener noreferrer"` from the title link
- [x] 1.2 In `views/triage.erb`, add a "Source →" link in the meta row pointing to `article['url']` with `target="_blank" rel="noopener noreferrer"` (only when `article['url']` is present) — place it where "Open in app" currently sits
- [x] 1.3 In `views/triage.erb`, remove the "Open in app →" link and its surrounding `<span>` separator

## 2. Digest

- [x] 2.1 In `app/digests.rb` `render_item_html`, change the title anchor href from `url` (external) to `/article/#{row['uid']}` and remove `target="_blank"`
- [x] 2.2 In `app/digests.rb` `render_item_html`, add a "Source" link in the meta line that links to `url` with `target="_blank" rel="noopener"` (only when `url` is non-empty)

## 3. Tests

- [x] 3.1 Verify existing triage-related specs still pass; add/update a spec asserting the triage card title links to `/article/:uid` and includes a Source link
- [x] 3.2 Verify existing digest specs still pass; add/update a spec asserting digest item title links to `/article/:uid` and includes a Source link
