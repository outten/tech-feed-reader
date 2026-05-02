#!/usr/bin/env ruby
# Seed the feeds table from FeedCatalog::seed_defaults — the curated
# starter subset of the catalog (entries flagged `seed: true`). Five
# feeds covering high-frequency aggregators, mainstream publishers, and
# one personal blog. Idempotent — re-running skips anything already
# subscribed, so it's safe to call after the user has added their own.
#
# Browse + add the rest of the 25-feed catalog from /feeds (see the
# "Discover popular feeds" section).
require_relative '../app/database'
require_relative '../app/feeds_store'
require_relative '../app/feed_catalog'

Database.migrate!

added   = 0
skipped = 0

FeedCatalog.seed_defaults.each do |entry|
  if FeedsStore.find_by_url(entry[:url])
    skipped += 1
    puts "skip   #{entry[:title]} (already subscribed)"
  else
    FeedsStore.add(
      url:                    entry[:url],
      title:                  entry[:title],
      fetch_interval_seconds: entry[:interval]
    )
    added += 1
    puts "add    #{entry[:title]} (#{entry[:interval]}s)"
  end
end

puts ''
puts "Seeded #{added} feed#{'s' unless added == 1}; #{skipped} already present."
puts "Browse the rest of the catalog at /feeds → 'Discover popular feeds'."
