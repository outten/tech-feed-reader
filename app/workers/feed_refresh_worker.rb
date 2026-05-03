require 'sidekiq'
require_relative '../scheduler'
require_relative '../feeds_store'
require_relative '../logger'

# Background job that refreshes a single feed. Enqueued by the
# /admin/refresh routes so the web request that triggered the refresh
# returns immediately while the actual fetch + sanitize + import runs
# on the worker process.
#
# Idempotent: ArticlesStore.import is keyed on article uid so re-runs
# don't duplicate. If the feed was deleted between enqueue and run we
# log and return without crashing the job.
class FeedRefreshWorker
  include Sidekiq::Worker

  # Default queue + retry policy is fine for now (Sidekiq retries with
  # exponential backoff, ~25 attempts over 21 days). Feed fetches are
  # cheap and idempotent so retries are safe.
  sidekiq_options queue: :default

  def perform(feed_id)
    feed = FeedsStore.find(feed_id.to_i)
    unless feed
      AppLogger.warn('feed_refresh_worker_skip', feed_id: feed_id, reason: 'not_found')
      return
    end

    Scheduler.refresh_one(feed)
  end
end
