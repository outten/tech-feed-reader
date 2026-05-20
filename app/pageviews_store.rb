require_relative 'database'

# STUFF #48.1 — wrapper around the `pageviews` table. Three call
# sites: RequestLogMiddleware (insert per request), /admin/analytics
# (aggregates for the 14-day window), /admin/users (cross-reference
# users to their last_seen_at-ish activity).
#
# All writes happen on the request hot path so this module stays
# single-purpose: one INSERT, no transactions, no batching. Reads
# fire only on the admin pages, so the aggregation queries can lean
# on the (section, occurred_at) + (user_id, occurred_at) indexes
# without per-query optimisation tricks.
module PageviewsStore
  module_function

  def db
    Database.connection
  end

  # Single-row INSERT from the middleware. user_id is nil for
  # anonymous visitors; section is nil when the path didn't match
  # any of the PageviewSection patterns. Returns nil — callers
  # don't need the row back.
  def record!(user_id:, path:, section:, status:)
    db.execute(
      'INSERT INTO pageviews(user_id, path, section, status) VALUES (?, ?, ?, ?)',
      [user_id && user_id.to_i, path.to_s, section, status.to_i]
    )
    nil
  end

  # Sum per day for the last N days. Returns Array<{day, count}>
  # ordered ASC; days with zero hits are NOT padded (callers do
  # that — view-level zero-fill is cheaper than a SQL date-series
  # join across both dialects).
  def daily_totals(days: 14)
    sql = <<~SQL
      SELECT #{Database.date_sql('occurred_at')} AS day, COUNT(*) AS count
      FROM pageviews
      WHERE occurred_at >= ?
      GROUP BY day
      ORDER BY day ASC
    SQL
    db.execute(sql, [since_iso(days)]).map { |r| { 'day' => r['day'].to_s, 'count' => r['count'].to_i } }
  end

  # Per-section totals (last N days). Returns Array<{section, count}>
  # ordered by count DESC. Nil-section rows show up as 'other'.
  def section_totals(days: 14)
    sql = <<~SQL
      SELECT COALESCE(section, 'other') AS section, COUNT(*) AS count
      FROM pageviews
      WHERE occurred_at >= ?
      GROUP BY COALESCE(section, 'other')
      ORDER BY count DESC
    SQL
    db.execute(sql, [since_iso(days)]).map { |r| { 'section' => r['section'].to_s, 'count' => r['count'].to_i } }
  end

  def total(days: 14)
    db.execute(
      'SELECT COUNT(*) AS c FROM pageviews WHERE occurred_at >= ?',
      [since_iso(days)]
    ).first['c'].to_i
  end

  # Opportunistic retention sweep — fired from /admin/analytics. Cheap
  # query (range scan over occurred_at index) so even a many-thousand-
  # row delete completes in a few ms. Returns the deleted count for
  # logging.
  def prune_older_than!(days: 90)
    cutoff = since_iso(days)
    rows_before = db.execute('SELECT COUNT(*) AS c FROM pageviews WHERE occurred_at < ?', [cutoff]).first['c'].to_i
    db.execute('DELETE FROM pageviews WHERE occurred_at < ?', [cutoff])
    rows_before
  end

  def since_iso(days)
    (Time.now.utc - (days.to_i * 86_400)).iso8601
  end
end
