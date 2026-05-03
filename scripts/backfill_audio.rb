#!/usr/bin/env ruby
# One-shot backfill for articles whose audio_url is NULL but whose
# source feed actually publishes an enclosure. Earlier ingestion runs
# (before the audio columns existed, or with an interim version of the
# import path) left a long tail of podcast rows with empty audio
# fields; the regular refresh path can't fix this because import uses
# INSERT OR IGNORE keyed on uid, so existing rows are never updated.
#
# Strategy: for each subscribed feed, fetch + parse fresh, then for
# every parsed entry that has an audio_url, UPDATE the matching
# articles row (by feed_id + uid) where audio_url IS NULL. Idempotent
# and safe to re-run — already-populated rows are not touched, and
# entries without enclosures are skipped.
#
# Usage:
#   bundle exec ruby scripts/backfill_audio.rb
require_relative '../app/database'
require_relative '../app/feeds_store'
require_relative '../app/feed_fetcher'

Database.migrate!
db = Database.connection

update_sql = <<~SQL
  UPDATE articles
     SET audio_url              = ?,
         audio_mime_type        = ?,
         audio_duration_seconds = ?
   WHERE feed_id   = ?
     AND uid       = ?
     AND audio_url IS NULL
SQL

totals = { feeds: 0, fetched: 0, updated: 0, skipped: 0 }

FeedsStore.all.each do |feed|
  totals[:feeds] += 1
  label = feed['title'] || feed['url']

  result = FeedFetcher.fetch_feed(feed.merge('last_etag' => nil, 'last_modified' => nil))
  unless result.status == :ok
    puts "skip   #{label} (status=#{result.status})"
    totals[:skipped] += 1
    next
  end
  totals[:fetched] += 1

  updated_for_feed = 0
  db.transaction do
    result.entries.each do |entry|
      next if entry[:audio_url].to_s.empty?
      db.execute(update_sql, [
        entry[:audio_url],
        entry[:audio_mime_type],
        entry[:audio_duration_seconds],
        feed['id'],
        entry[:uid]
      ])
      updated_for_feed += db.changes
    end
  end

  totals[:updated] += updated_for_feed
  puts "ok     #{label} (+#{updated_for_feed})"
end

puts ''
puts "Backfill complete: feeds=#{totals[:feeds]} fetched=#{totals[:fetched]} " \
     "updated=#{totals[:updated]} skipped=#{totals[:skipped]}"
