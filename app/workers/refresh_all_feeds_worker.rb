require 'sidekiq'
require_relative '../feeds_store'
require_relative 'feed_refresh_worker'
require_relative '../logger'

# Hourly fan-out worker triggered by sidekiq-cron. Walks FeedsStore.all
# and enqueues one FeedRefreshWorker per feed — same semantics as the
# header "Refresh all" button + the /refresh/all route.
#
# Idempotent and safe to run concurrently with manual refreshes:
# FeedRefreshWorker is keyed on feed_id and uses ArticlesStore.import's
# uid-based dedupe.
class RefreshAllFeedsWorker
  include Sidekiq::Worker

  sidekiq_options queue: :default, retry: 2

  def perform
    feeds = FeedsStore.all
    feeds.each { |feed| FeedRefreshWorker.perform_async(feed['id']) }
    AppLogger.info('refresh_all_enqueued', count: feeds.length, source: 'cron')
  end
end
