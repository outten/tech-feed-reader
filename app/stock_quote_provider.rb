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
  # Finnhub free tier doesn't support CFD index symbols (^GSPC etc.),
  # so we use liquid US-listed ETFs that track each index.  The display
  # name still says "S&P 500" — the ETF ticker is shown as a subtitle.
  MAJOR_INDICES = [
    { symbol: 'SPY',  name: 'S&P 500',             exchange: 'INDEX' },
    { symbol: 'DIA',  name: 'Dow Jones Industrial', exchange: 'INDEX' },
    { symbol: 'QQQ',  name: 'NASDAQ Composite',     exchange: 'INDEX' },
    { symbol: 'IWM',  name: 'Russell 2000',         exchange: 'INDEX' },
    { symbol: 'EWU',  name: 'FTSE 100 (UK)',        exchange: 'INDEX' },
    { symbol: 'EWG',  name: 'DAX (Germany)',         exchange: 'INDEX' },
    { symbol: 'EWJ',  name: 'Nikkei 225 (Japan)',    exchange: 'INDEX' },
    { symbol: 'EWH',  name: 'Hang Seng (HK)',        exchange: 'INDEX' },
    { symbol: 'EWQ',  name: 'CAC 40 (France)',       exchange: 'INDEX' },
    { symbol: 'FEZ',  name: 'Euro Stoxx 50',         exchange: 'INDEX' }
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

  # Intraday sparkline via Yahoo Finance (free, no key needed).
  # Returns an array of close prices (5-min intervals, ~78 points for a
  # full trading day) or [] on failure.  Used for the index card charts.
  YAHOO_CHART_URL = 'https://query1.finance.yahoo.com/v8/finance/chart'

  def sparkline(symbol, range: '1d', interval: '5m')
    sym = symbol.to_s.upcase
    uri = URI("#{YAHOO_CHART_URL}/#{ERB::Util.url_encode(sym)}")
    uri.query = URI.encode_www_form(range: range, interval: interval)

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
      req = Net::HTTP::Get.new(uri.request_uri)
      req['User-Agent'] = 'Mozilla/5.0'
      http.request(req)
    end

    return [] unless response.code.to_i == 200

    data = JSON.parse(response.body)
    closes = data.dig('chart', 'result', 0, 'indicators', 'quote', 0, 'close') || []
    closes.compact.map { |c| c.round(2) }
  rescue StandardError => e
    AppLogger.warn('stock_provider', message: "sparkline failed for #{sym}", error: e.message)
    []
  end

  # Batch sparklines for all major indices.  Returns { "SPY" => [...], ... }.
  def sparklines_for_indices
    MAJOR_INDICES.each_with_object({}) do |idx, h|
      h[idx[:symbol]] = sparkline(idx[:symbol])
    end
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
