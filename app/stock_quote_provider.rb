require 'net/http'
require 'json'
require 'uri'
require_relative 'stock_quotes_store'
require_relative 'logger'

# Thin wrapper around the Finnhub REST API (free tier: 60 req/min).
# Provides symbol search, real-time quotes, and company profiles.
#
# All methods are no-ops (return empty / nil) when FINNHUB_API_KEY
# is unset, matching the graceful-degradation pattern used by the
# Claude summarizer.
module StockQuoteProvider
  BASE = 'https://finnhub.io/api/v1'

  # Major world indices presented to users on the stocks browse page.
  # Finnhub uses the exchange-prefixed format for non-US tickers.
  MAJOR_INDICES = [
    { symbol: '^GSPC',  name: 'S&P 500',            exchange: 'INDEX' },
    { symbol: '^DJI',   name: 'Dow Jones Industrial', exchange: 'INDEX' },
    { symbol: '^IXIC',  name: 'NASDAQ Composite',    exchange: 'INDEX' },
    { symbol: '^RUT',   name: 'Russell 2000',        exchange: 'INDEX' },
    { symbol: '^FTSE',  name: 'FTSE 100',            exchange: 'INDEX' },
    { symbol: '^GDAXI', name: 'DAX (Germany)',        exchange: 'INDEX' },
    { symbol: '^N225',  name: 'Nikkei 225',           exchange: 'INDEX' },
    { symbol: '^HSI',   name: 'Hang Seng',            exchange: 'INDEX' },
    { symbol: '^FCHI',  name: 'CAC 40 (France)',      exchange: 'INDEX' },
    { symbol: '^STOXX', name: 'Euro Stoxx 50',        exchange: 'INDEX' }
  ].freeze

  module_function

  def api_key
    ENV['FINNHUB_API_KEY']
  end

  def available?
    !api_key.to_s.strip.empty?
  end

  # Search for a symbol by company name or partial ticker.
  # Returns an array of { symbol:, description:, type: } hashes.
  def search(query)
    return [] unless available?

    data = get('/search', q: query)
    return [] unless data && data['result']

    data['result'].map do |r|
      { symbol: r['symbol'], description: r['description'], type: r['type'] }
    end
  end

  # Real-time quote for a single symbol.
  # Returns { c: current, d: change, dp: change%, h: high, l: low,
  #           o: open, pc: prev_close, t: timestamp } or nil.
  def quote(symbol)
    return nil unless available?

    get('/quote', symbol: symbol.to_s.upcase)
  end

  # Company profile (name, exchange, sector, logo, market cap, etc.)
  # Returns the Finnhub profile2 hash or nil.
  def profile(symbol)
    return nil unless available?

    get('/stock/profile2', symbol: symbol.to_s.upcase)
  end

  # Fetch quote + profile from Finnhub and cache in stock_quotes.
  # Called on follow (immediate) and by the periodic sync worker.
  def fetch_and_cache(symbol)
    sym = symbol.to_s.upcase
    return unless available?

    q = quote(sym)
    p = profile(sym)

    # q can be empty for indices on free tier — still cache what we have
    data = {}
    if q && q['c'] && q['c'].to_f.positive?
      data.merge!(
        price:      q['c'],
        change:     q['d'],
        change_pct: q['dp'],
        day_high:   q['h'],
        day_low:    q['l'],
        open:       q['o'],
        prev_close: q['pc']
      )
    end

    if p && !p.empty? && p['name']
      data.merge!(
        name:       p['name'],
        exchange:   p['exchange'],
        sector:     p['finnhubIndustry'],
        industry:   p['finnhubIndustry'],
        market_cap: p['marketCapitalization'] ? (p['marketCapitalization'].to_f * 1_000_000).to_i : nil,
        logo:       p['logo']
      )
    end

    StockQuotesStore.upsert(symbol: sym, **data) unless data.empty?
    data
  rescue StandardError => e
    AppLogger.warn('stock_provider', message: "fetch_and_cache failed for #{sym}", error: e.message)
    nil
  end

  # --- private HTTP helper -----------------------------------------------

  def get(path, **params)
    params[:token] = api_key
    uri = URI("#{BASE}#{path}")
    uri.query = URI.encode_www_form(params)

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
      http.get(uri.request_uri)
    end

    case response.code.to_i
    when 200
      JSON.parse(response.body)
    when 429
      AppLogger.warn('stock_provider', message: 'Finnhub rate limit hit, sleeping 1s')
      sleep 1
      nil
    else
      AppLogger.warn('stock_provider', message: "Finnhub #{path} returned #{response.code}", body: response.body&.slice(0, 200))
      nil
    end
  rescue StandardError => e
    AppLogger.warn('stock_provider', message: "Finnhub HTTP error: #{e.message}")
    nil
  end
end
