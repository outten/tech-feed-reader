require 'sidekiq'
require_relative '../stock_quote_provider'
require_relative '../logger'

# Eager fetch of a single stock quote right after a user follows it.
# Without this, a newly-followed symbol would sit empty on the ticker
# until the next periodic sync. Enqueued from POST /stocks/follow so
# the user sees data within seconds of clicking the button.
class StockQuoteFetchWorker
  include Sidekiq::Worker

  sidekiq_options queue: :default, retry: 2

  def perform(symbol)
    sym = symbol.to_s.upcase
    result = StockQuoteProvider.fetch_and_cache(sym)
    if result
      AppLogger.info('stock_quote_fetch', symbol: sym, status: 'ok')
    else
      AppLogger.warn('stock_quote_fetch', symbol: sym, status: 'empty_or_failed')
    end
  end
end
