-- STUFF #61 — track whether an article's content_html has been run
-- through the link-absolutize scrubber (Sanitizer with base_url:).
-- New imports set TRUE on insert; the `make fix-article-links`
-- maintenance script filters WHERE content_scrubbed = FALSE and
-- bumps it to TRUE after rewriting. NOT NULL DEFAULT FALSE so every
-- existing row gets a definite "not yet scrubbed" value and the
-- maintenance script picks them all up on first run.
ALTER TABLE articles ADD COLUMN content_scrubbed BOOLEAN NOT NULL DEFAULT FALSE;
