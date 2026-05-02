#!/usr/bin/env ruby
# Seed the feeds table with the v1-kickoff starter set: 5 feeds chosen
# to validate the pipeline (high-frequency, publisher, and personal-blog
# cadences all represented).
#
# Idempotent — skips any URL already present, so re-running after the
# user adds their own feeds via /feeds is safe.
require_relative '../app/database'
require_relative '../app/feeds_store'

# Apply schema before we write — the script can be run before the web
# app's auto-migrate has had a chance to fire.
Database.migrate!

SEED_FEEDS = [
  {
    url:                    'https://news.ycombinator.com/rss',
    title:                  'Hacker News',
    fetch_interval_seconds: FeedsStore::HIGH_FREQUENCY_INTERVAL
  },
  {
    url:                    'https://lobste.rs/rss',
    title:                  'Lobsters',
    fetch_interval_seconds: FeedsStore::HIGH_FREQUENCY_INTERVAL
  },
  {
    url:                    'https://feeds.arstechnica.com/arstechnica/index',
    title:                  'Ars Technica',
    fetch_interval_seconds: FeedsStore::PUBLISHER_INTERVAL
  },
  {
    url:                    'https://www.theverge.com/rss/index.xml',
    title:                  'The Verge',
    fetch_interval_seconds: FeedsStore::PUBLISHER_INTERVAL
  },
  {
    url:                    'https://simonwillison.net/atom/everything/',
    title:                  'Simon Willison',
    fetch_interval_seconds: FeedsStore::PERSONAL_BLOG_INTERVAL
  }
].freeze

added   = 0
skipped = 0

SEED_FEEDS.each do |feed|
  if FeedsStore.find_by_url(feed[:url])
    skipped += 1
    puts "skip   #{feed[:title]} (already subscribed)"
  else
    FeedsStore.add(**feed)
    added += 1
    puts "add    #{feed[:title]} (#{feed[:fetch_interval_seconds]}s)"
  end
end

puts "\nSeeded #{added} feed#{'s' unless added == 1}; #{skipped} already present."
