require 'sidekiq'
require_relative '../stock_follows_store'
require_relative '../stock_quote_provider'
require_relative '../logger'

# Periodic bulk refresh of all followed stock symbols. Enqueue this
# from the scheduler or cron (e.g. every 15 minutes during market hours).
#
# Finnhub free tier: 60 req/min. Each symbol needs ~2 API calls
# (quote + profile), so we throttle to ~1 symbol/sec to stay safe.
# With 30 followed symbols, a full sync takes ~30s.
class StockSyncWorker
  include Sidekiq::Worker

  sidekiq_options queue: :default, retry: 1

  def perform
    symbols = StockFollowsStore.distinct_symbols
    AppLogger.info('stock_sync_start', count: symbols.size)

    symbols.each_with_index do |sym, i|
      # Throttle: Finnhub free = 60/min, 2 calls per symbol → ~1/sec
      sleep(1.1) if i.positive?
      StockQuoteProvider.fetch_and_cache(sym)
    end

    AppLogger.info('stock_sync_done', count: symbols.size)
  end
end
