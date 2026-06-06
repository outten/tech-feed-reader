require 'sidekiq'
require_relative '../stock_quote_provider'
require_relative '../logger'

# Periodic refresh of the MAJOR_INDICES quotes (S&P 500, Dow, NASDAQ,
# FTSE, DAX, Nikkei, etc.).  These are displayed on /stocks regardless
# of whether anyone has explicitly followed them, so they need their
# own sync cadence separate from StockSyncWorker (which only refreshes
# user-followed symbols).
#
# Finnhub free tier: 60 req/min.  10 indices × ~2 calls each = ~20
# API calls.  With 1.1 s sleep between symbols the full run takes ~11 s.
class IndexSyncWorker
  include Sidekiq::Worker

  sidekiq_options queue: :default, retry: 1

  def perform
    indices = StockQuoteProvider::MAJOR_INDICES
    AppLogger.info('index_sync_start', count: indices.size)

    indices.each_with_index do |idx, i|
      sleep(1.1) if i.positive?
      StockQuoteProvider.fetch_and_cache(idx[:symbol])
    end

    AppLogger.info('index_sync_done', count: indices.size)
  end
end
