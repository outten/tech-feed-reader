require_relative 'feeds_store'

# Maps a stock/index symbol to its Yahoo Finance per-symbol RSS feed, so
# a followed symbol's news flows through the ordinary feed → article
# pipeline (and therefore surfaces in /articles + the home page) and the
# /stocks/:symbol page can show recent headlines.
#
# Yahoo still publishes a standard RSS 2.0 headline feed per ticker (no
# API key); it works for ETF tickers too (SPY, QQQ, …) so the major
# indices get news as well. Each symbol becomes one row in the shared
# `feeds` catalog with topic 'finance'.
module StockNewsFeed
  module_function

  # 1 hour — news doesn't change minute-to-minute, and the hourly
  # RefreshAllFeedsWorker already walks every catalog row.
  FETCH_INTERVAL = 3600

  # Substring that identifies an auto-created stock feed, so these rows
  # can be kept out of the /feeds management list (they're managed via
  # the /stocks follow toggle instead).
  URL_MARKER = 'feeds.finance.yahoo.com/rss/2.0/headline'

  def url_for(symbol)
    sym = symbol.to_s.strip.upcase
    "https://feeds.finance.yahoo.com/rss/2.0/headline?s=#{sym}&region=US&lang=en-US"
  end

  def stock_feed?(url)
    url.to_s.include?(URL_MARKER)
  end

  # Idempotent: returns the existing-or-newly-created feed row for the
  # symbol. `name` is the company name (from the cached quote) used for a
  # friendlier title; falls back to the bare symbol.
  def ensure_feed!(symbol, name = nil)
    sym   = symbol.to_s.strip.upcase
    label = name.to_s.strip.empty? ? sym : "#{name.strip} (#{sym})"
    FeedsStore.add_to_catalog(
      url:   url_for(sym),
      title: "#{label} — News",
      fetch_interval_seconds: FETCH_INTERVAL,
      topic: 'finance'
    )
  end
end
