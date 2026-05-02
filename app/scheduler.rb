require 'time'
require_relative 'feeds_store'
require_relative 'articles_store'
require_relative 'feed_fetcher'

# Polling logic shared by the long-running scripts/scheduler.rb, the
# one-shot scripts/refresh_*.rb scripts, and the admin /admin/refresh
# routes.
#
# Pure functions on top of the existing stores — no global state of its
# own. The actual sleep loop lives in scripts/scheduler.rb so the main
# app process never blocks.
module Scheduler
  module_function

  # A feed is due when it has never been fetched OR
  # last_fetched_at + fetch_interval_seconds <= now.
  def due?(feed, now: Time.now.utc)
    last_iso = feed['last_fetched_at'].to_s
    return true if last_iso.empty?

    last = (Time.parse(last_iso) rescue nil)
    return true if last.nil?

    (last + feed['fetch_interval_seconds'].to_i) <= now
  end

  # Returns the subset of `feeds` that are due. Caller decides ordering;
  # the scheduler script processes them in id order to make logs
  # predictable.
  def due_feeds(feeds, now: Time.now.utc)
    feeds.select { |f| due?(f, now: now) }
  end

  # Fetch + sanitize + import for one feed row. Returns
  # [FeedFetcher::Result, imported_count]. The HealthRegistry hook is
  # already inside FeedFetcher.fetch_feed, so /admin/health surfaces
  # observations from CLI runs too.
  def refresh_one(feed)
    result   = FeedFetcher.fetch_feed(feed)
    imported = result.status == :ok ? ArticlesStore.import(feed_id: feed['id'], entries: result.entries) : 0
    [result, imported]
  end
end
