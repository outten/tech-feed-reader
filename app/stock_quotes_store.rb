require_relative 'database'

# Cached stock quote data. One row per symbol, updated by the sync
# worker. The ticker bar and /stocks/:symbol detail page read from
# here — never from the Finnhub API on page render.
module StockQuotesStore
  module_function

  def db
    Database.connection
  end

  # Single quote row or nil.
  def find(symbol)
    db.execute(
      'SELECT * FROM stock_quotes WHERE symbol = $1',
      [symbol.to_s.upcase]
    ).first
  end

  # Multiple quote rows for the ticker bar.
  def find_many(symbols)
    return [] if symbols.empty?

    placeholders = symbols.each_with_index.map { |_, i| "$#{i + 1}" }.join(', ')
    db.execute(
      "SELECT * FROM stock_quotes WHERE symbol IN (#{placeholders}) ORDER BY symbol",
      symbols.map { |s| s.to_s.upcase }
    )
  end

  # Upsert a quote snapshot. data is a Hash with string or symbol keys
  # matching the column names (name, exchange, sector, industry,
  # market_cap, logo, price, change, change_pct, day_high, day_low,
  # open, prev_close, volume).
  def upsert(symbol:, **data)
    sym = symbol.to_s.upcase
    args = [
      sym,
      data[:name],       data[:exchange],   data[:sector],
      data[:industry],   data[:market_cap], data[:logo],
      data[:price],      data[:change],     data[:change_pct],
      data[:day_high],   data[:day_low],    data[:open],
      data[:prev_close], data[:volume]
    ]
    sql = <<~SQL
      INSERT INTO stock_quotes
        (symbol, name, exchange, sector, industry, market_cap, logo,
         price, change, change_pct, day_high, day_low, open, prev_close, volume, updated_at)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, now()::text)
      ON CONFLICT (symbol) DO UPDATE SET
        name       = COALESCE(EXCLUDED.name,       stock_quotes.name),
        exchange   = COALESCE(EXCLUDED.exchange,    stock_quotes.exchange),
        sector     = COALESCE(EXCLUDED.sector,      stock_quotes.sector),
        industry   = COALESCE(EXCLUDED.industry,    stock_quotes.industry),
        market_cap = COALESCE(EXCLUDED.market_cap,  stock_quotes.market_cap),
        logo       = COALESCE(EXCLUDED.logo,        stock_quotes.logo),
        price      = COALESCE(EXCLUDED.price,       stock_quotes.price),
        change     = COALESCE(EXCLUDED.change,      stock_quotes.change),
        change_pct = COALESCE(EXCLUDED.change_pct,  stock_quotes.change_pct),
        day_high   = COALESCE(EXCLUDED.day_high,    stock_quotes.day_high),
        day_low    = COALESCE(EXCLUDED.day_low,     stock_quotes.day_low),
        open       = COALESCE(EXCLUDED.open,        stock_quotes.open),
        prev_close = COALESCE(EXCLUDED.prev_close,  stock_quotes.prev_close),
        volume     = COALESCE(EXCLUDED.volume,      stock_quotes.volume),
        updated_at = now()::text
    SQL
    db.execute(sql, args)
  end

  # Is the cached quote older than max_age_seconds?
  def stale?(symbol, max_age_seconds: 300)
    row = find(symbol)
    return true if row.nil?

    begin
      updated = Time.parse(row['updated_at'])
    rescue StandardError
      return true
    end
    (Time.now - updated) > max_age_seconds
  end
end
