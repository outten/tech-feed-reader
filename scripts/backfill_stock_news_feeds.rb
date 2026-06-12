#!/usr/bin/env ruby
# One-shot reconcile so that stock follows created BEFORE the per-symbol
# news feature get their news feed too. For every row in stock_follows:
#   1. ensure the symbol's Yahoo RSS feed exists (StockNewsFeed),
#   2. subscribe the follower to it (so its articles show in /articles +
#      the home page — same as a fresh follow does), and
#   3. do an initial fetch for any feed that has no articles yet, so the
#      surfaces aren't empty on first load.
#
# Idempotent: subscribe is ON CONFLICT DO NOTHING, ensure_feed! returns
# the existing row, and only feeds with zero articles are fetched. Safe
# to re-run.
#
# Usage:
#   make backfill-stock-news
#   bundle exec ruby scripts/backfill_stock_news_feeds.rb

require_relative '../app/credentials'
require_relative '../app/database'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/scheduler'
require_relative '../app/stock_news_feed'
require_relative '../app/logger'

Database.migrate!

follows = Database.connection.execute(
  'SELECT user_id, symbol, name FROM stock_follows ORDER BY symbol, user_id'
)

if follows.empty?
  puts 'No stock follows. Nothing to do.'
  exit 0
end

puts "Reconciling #{follows.length} stock follow#{'s' unless follows.length == 1}…"

subscribed = 0
fetched    = 0
fetched_feeds = {} # feed_id → true, so we fetch each cold feed at most once

follows.each do |row|
  symbol = row['symbol']
  feed   = StockNewsFeed.ensure_feed!(symbol, row['name'])

  if FeedsStore.subscribe(row['user_id'], feed['id'])
    puts "  ✓ user=#{row['user_id']} subscribed to #{symbol} (feed_id=#{feed['id']})"
    subscribed += 1
  end

  # Prime the feed once if it has no articles yet.
  next if fetched_feeds[feed['id']]

  has_articles = ArticlesStore.recent_for_feed(row['user_id'], feed['id'], limit: 1).any?
  next if has_articles

  fetched_feeds[feed['id']] = true
  result, imported = Scheduler.refresh_one(feed)
  puts "  · fetched #{symbol}: status=#{result.status} imported=#{imported}"
  fetched += 1
  # Gentle pause — Yahoo + per-article readability fetches. Mirrors the
  # throttle in the other backfill scripts.
  sleep 0.5
end

puts
puts "Done. new_subscriptions=#{subscribed} feeds_fetched=#{fetched}"
