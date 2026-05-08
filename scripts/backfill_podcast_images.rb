#!/usr/bin/env ruby
# Cosmetics 6 — one-shot sweep that fills feeds.image_url for podcast
# feeds where it's currently null/empty. Walks every feed that has
# at least one article with audio_url (i.e. is functionally a
# podcast) and runs a Providers::ITunesLookup against the title.
#
# Idempotent: skips feeds that already have an image_url. Safe to
# re-run after adding new podcasts.
#
# Usage:
#   make backfill-podcast-images
#   bundle exec ruby scripts/backfill_podcast_images.rb

require_relative '../app/credentials'
require_relative '../app/database'
require_relative '../app/feeds_store'
require_relative '../app/providers/itunes_lookup'
require_relative '../app/logger'

Database.migrate!

candidates = Database.connection.execute(<<~SQL)
  SELECT f.id, f.title, f.url
  FROM feeds f
  WHERE (f.image_url IS NULL OR TRIM(f.image_url) = '')
    AND EXISTS (
      SELECT 1 FROM articles a
      WHERE a.feed_id = f.id AND a.audio_url IS NOT NULL
    )
  ORDER BY f.id
SQL

if candidates.empty?
  puts 'No podcast feeds are missing image_url. Nothing to do.'
  exit 0
end

puts "Backfilling cover art for #{candidates.length} podcast feed#{'s' unless candidates.length == 1}…"

found  = 0
missed = 0

candidates.each do |feed|
  title = feed['title'].to_s.strip
  if title.empty?
    puts "  feed_id=#{feed['id']} url=#{feed['url']} — no title, skipping"
    missed += 1
    next
  end

  result = Providers::ITunesLookup.find_artwork(title)
  case result.status
  when :ok
    Database.connection.execute('UPDATE feeds SET image_url = ? WHERE id = ?', [result.artwork_url, feed['id']])
    puts "  ✓ #{title.inspect} → #{result.artwork_url}"
    found += 1
  when :not_found
    puts "  · #{title.inspect} → no iTunes match"
    missed += 1
  else
    puts "  ✗ #{title.inspect} → #{result.error}"
    missed += 1
  end

  # Gentle pause so we don't blow through Apple's rate limit on big
  # backfills. Apple advertises ~20 req/min for unauthenticated calls.
  sleep 0.5
end

puts
puts "Done. found=#{found} missed=#{missed}"
