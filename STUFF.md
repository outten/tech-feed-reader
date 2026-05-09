# Stuff

Random stuff to add to the application.

## [x] CLAUDE_API_KEY

I added my Claude API Key and Name to the .credentials file. Can you integrate and create tests to make sure it works? Implement how it will be used in the application. Also, add a Chat Widget to the application that uses it. Put a chat button on each page at the bottom right that will show a panel for chatting with the context of the page.

Done in commits `bded707` (widget + Chat::Claude module + 22 specs) and `d130a17` (default-closed CSS fix). Verified end-to-end: real PONG round-trip + grounded answer using article excerpt as page context.

## [x] White Listed Shell Actions

I am constantly being asked to approve safe commands like curl, echo, etc. Can you check the VS Code settings for Claude to whitelist all simple shell commands. You did this in a prior commit; however, it is not working.

## [x] Clean Up Branch 001

Let's take a branch to stop and cleanup some items:

- let's be sure to have tooltips for all relevant elements on pages
- on the article page, the Comment and Reload button are stacked horizontally which looks strange, can you do separate buttoms that are verticle with the save this story element
- can you make sure any images for articles and podcasts are used
  - for example, oftentimes a podcast has a Cover Art Picture
- on the UI side, I love inspirational nature pictures, can we use random, free, copyright free pictures as the background on each page ... it should not scroll with the page elements. This may make the look and feel more pleasing.

## [x] Bus Mode

I have a 10-15 minute commute on a SEPTA, Philadelphia, PA bus every day. On most commutes, I listen to a podcast. 

Can you add a Bus Icon in the header before the Refresh All button that will list recent podcasts in order that are less than 15 minutes. Include the usual information for each podcast on the Podcast page. In the same tile format.

## [x] Claude Summarization of a Digest

Add a button on the digest page to have Claude summarize it. Be sure to store the AI summary so we don't have to do it again and waste tokens.

Done on outten/TODO-046. New `Summarizer::Claude.summarize_digest` + cached on the `digests` row via three new columns (`llm_summary`, `llm_model`, `llm_generated_at`, migration `009_digest_llm_summary.sql`). The detail page shows the cached summary above `html_body`; the "Summarize with Claude" button only renders when no cache exists, and the route hard-skips the API call (with a "no new API call was made" notice) if a summary is already stored. 18 examples in `spec/digest_llm_summary_spec.rb`.

## [x] Cosmetics

Shipped in commit `42040f4` (Cosmetics sweep + skim-mode page-preservation bug fix). All seven sub-items merged in one PR; doc catch-up for AGENTS.md followed in `5e637db`.

### [x] 1+2. Sticky-pin on `/article/:uid` (and the title cramp it caused)

> "On the top of page element in the article section, I see that the title of the article is jammed into a column that is too small with width."
> "On the articles page for an article, scrolling pins the first element at the top which is weird and makes it hard to read the other content."

These were the same bug. The global rule `header { position: sticky; top: 0 }` in style.css unintentionally also targeted the inner `<header>` inside `<article class="reading-view"><header>...</header></article>`, pinning the entire article header (hero image + title + subtitle + actions row + tags) to the top while you scrolled the body — which is why both the title looked jammed (squashed into a sticky column) and the rest of the page felt wrong. Fix: scope the sticky to `body > header` only.

### [x] 3. Podcast actions row overflows on `/article/:uid`

> "On the articles page for a podcast, the top element that have a picture of the podcast, pause/play button, mark unread, etc. doesn't fit in the element so things are rendering outside the element."

`.reading-view .actions` was a flat flexbox with no `flex-wrap`. After Phases 3 + 5 added 👍 / 👎 / Mute author / Mute keyword (with an inline text input), the row ran past the right edge on narrow widths. Fix: `flex-wrap: wrap`, gap tightened, and the keyword-mute input narrowed so it doesn't dominate the wrap line.

### [x] 4. Skim-mode thumbnail overlaps the summary line

> "On the articles list page, when you engage skim mode, the picture on the right is over top of the first two lines of text."

`.news-summary-skim` only set a `margin-left` for icon alignment; it didn't reserve space on the right for the absolutely-positioned `.news-item-thumb` (64 px). Fix: hide the thumbnail entirely in skim mode — skim is for fast scan-and-triage, the picture isn't load-bearing here.

### [x] 5. Dashboard "Activity (last 30 days)" is empty

> "On the dashboard page, the 'Activity (last 30 days)' element has no content. Can you add what should be there? Or delete the element."

Real bug. `ArticlesStore.daily_counts(days: 30)` queries 30 days, but `RETENTION_DAYS=7` (the pruner sweeps anything older), so 23 of the 30 days are always zero. The chart shows axes + a flat line. Fix: drive the chart window from `RETENTION_DAYS` and re-label the section ("Activity (last N days)").

### [x] 6. Some podcasts on `/podcasts` are missing cover art

> "Some of the podcasts don't have pictures. I see them in my Apple Podcast app. For example, the 'The Ezra Klein Show'. No biggie if you can get it."

Genuine miss. `FeedParser` already extracts both `<itunes:image>` and `<image><url>`, but some publishers (Vox-published Ezra Klein among them) don't expose either at the channel level. Fix: new `Providers::ITunesLookup` module — queries the public iTunes Search API by show title, returns the first artwork URL — plus a one-shot `make backfill-podcast-images` script that fills `feeds.image_url` for podcast feeds where it's currently null.

### [x] 7. Verbose logging — dev DEBUG, request logs

> "Can you add more verbose logging. For example, I don't see page loads. Development environments should log DEBUG and above. Staging and production should log INFO and higher."

Two-part fix:
- `app/logger.rb` flips its default to `debug` when `RACK_ENV` is unset/development; stays `info` for `RACK_ENV=staging` and `production`; stays `fatal` for `test` (so RSpec output stays clean). `LOG_LEVEL` env var still overrides.
- New Sinatra `before` + `after` hooks emit a single `http_request` JSON line per request with `method`, `path`, `status`, `latency_ms`, `ip`. Logs every request including static assets (per the user's preference for full visibility).

## [ ] 8. Triage page 

The layout of the card elements on the page is off. For example, /triage/1 

- The title of the article is vertical instead of horizontal
- can you add a summary of the content for each card

## [ ] 9. Sports Scores

On the sports page, at the top, can you add tiles that show the last game score for the teams we are following. Include date, score, logos of teams, where played, and anything else relevant. Also, add the team's last game on the individual team page.

## [x] 10. Claude Behavior

Review CLAUDE.md file that contains behavior for Claude. Incorporate this, perhaps the AGENTS.md file might need updating.

CLAUDE.md is now tracked + referenced from AGENTS.md's Documentation files section. The two files are complementary, not overlapping: CLAUDE.md is general LLM-coding behaviour (think before coding, simplicity first, surgical changes, goal-driven execution); AGENTS.md is project-specific architecture (what the codebase looks like, conventions, gotchas). Future agents read both.
