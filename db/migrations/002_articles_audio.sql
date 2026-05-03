-- Migration 002 — audio columns on articles for podcast support.
--
-- A podcast episode is "an article with an audio enclosure." The
-- existing title / url / content_html / content_text fields hold the
-- show title and show notes; we just add the streaming-relevant audio
-- metadata so the article view can render a player.
--
-- All three columns are NULL on every existing row, which is exactly
-- what we want — non-podcast articles have no audio. New podcast
-- articles get the values from <enclosure ... type="audio/*"> on the
-- feed entry (parsed by feedjira; see app/feed_parser.rb).

ALTER TABLE articles ADD COLUMN audio_url              TEXT;
ALTER TABLE articles ADD COLUMN audio_mime_type        TEXT;
ALTER TABLE articles ADD COLUMN audio_duration_seconds INTEGER;
