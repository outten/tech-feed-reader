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

## [ ] Cosmetics

- on the top of page element in the article section, I see that the title of the article is jammed into a column that is too small with width. Consider having the title expand across all of the columns as one element. It should be able to be read clearly before the user decides if they want to engage it and/or thumbs up/down, etc it.
- on the aricles page for an article, scrolling pins the first element at the top which is weird and makes it hard to read the other content. Please review and fix.
- on the articles page for a podcast, the top element that have a picture of the podcast, pause/play button, mark unread, etc. doesn't fit in the element so things are rending outside the element. Can you fix, which can include a new layout.
- on the artiles list page, when you engage skim mode, the picture on the right is over top of the first two lines of text. Can you fix, which can include a new layout.
- on the dashboard page, the "Activity (last 30 days)" element has no content. Can you add what should be there? Or delete the element.
- on the podcasts page, some of the podcasts don't have pictures. I see them in my Apple Podcast app. For example, the "The Ezra Klein Show". Can you recheck to see if you can get a link to it or not? No biggie if you can get it.
- logging. Can you add more verbose logging. For example, I don't see page loads. development environments should log DEBUG and above. staging and production should log INFO and higher.



