require_relative 'database'

# Per-user stock symbol follows. Mirrors the sports_follows pattern:
# users follow ticker symbols, and a sync worker refreshes cached
# quotes for all followed symbols.
#
# The dashboard stock ticker reads from stock_quotes (cache), never
# from the Finnhub API on page render (cache-only contract).
module StockFollowsStore
  module_function

  def db
    Database.connection
  end

  # All symbols a user follows, ordered by follow time.
  def all(user_id)
    db.execute(
      'SELECT * FROM stock_follows WHERE user_id = $1 ORDER BY created_at',
      [user_id.to_i]
    )
  end

  # Boolean: does this user follow this symbol?
  def follow?(user_id, symbol)
    !db.execute(
      'SELECT 1 FROM stock_follows WHERE user_id = $1 AND symbol = $2 LIMIT 1',
      [user_id.to_i, symbol.to_s.upcase]
    ).first.nil?
  end

  # Idempotent — re-following is a no-op (UNIQUE(user_id, symbol)).
  # Returns true on insert, false on already-present.
  def add(user_id:, symbol:, name: nil)
    sym = symbol.to_s.strip.upcase
    raise ArgumentError, 'symbol must be non-empty' if sym.empty?

    db.execute(
      'INSERT INTO stock_follows(user_id, symbol, name) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING',
      [user_id.to_i, sym, name]
    )
    db.changes.positive?
  end

  def remove(user_id:, symbol:)
    db.execute(
      'DELETE FROM stock_follows WHERE user_id = $1 AND symbol = $2',
      [user_id.to_i, symbol.to_s.upcase]
    )
    db.changes
  end

  def count(user_id)
    db.execute(
      'SELECT COUNT(*) AS c FROM stock_follows WHERE user_id = $1',
      [user_id.to_i]
    ).first['c']
  end

  # Sync helper: all unique symbols across all users, so the periodic
  # sync job knows which quotes to refresh.
  def distinct_symbols
    db.execute(
      'SELECT DISTINCT symbol FROM stock_follows ORDER BY symbol'
    ).map { |r| r['symbol'] }
  end
end
