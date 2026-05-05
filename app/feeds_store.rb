require_relative 'database'

# Wrapper around the `feeds` table. Returns hash-rows (matching
# Database#results_as_hash) so callers can pass them straight into ERB.
#
# Schema is defined in db/migrations/001_init.sql. SQLite handles
# concurrency via WAL + the per-process Mutex inside Database; the
# transactions in INSERT/UPDATE/DELETE here are implicit.
module FeedsStore
  # Suggested defaults per AGENTS.md "Caching architecture" — the actual
  # value lives in feeds.fetch_interval_seconds, callers can override.
  HIGH_FREQUENCY_INTERVAL = 15 * 60       # 15 min
  PUBLISHER_INTERVAL      = 60 * 60       # 1 h
  PERSONAL_BLOG_INTERVAL  = 4 * 60 * 60   # 4 h

  module_function

  def all
    db.execute('SELECT * FROM feeds ORDER BY id ASC')
  end

  def find(id)
    db.execute('SELECT * FROM feeds WHERE id = ?', [id]).first
  end

  def find_by_url(url)
    db.execute('SELECT * FROM feeds WHERE url = ?', [url]).first
  end

  def count
    db.execute('SELECT COUNT(*) AS c FROM feeds').first['c']
  end

  # Add a new feed. Returns the inserted row's hash. Raises
  # SQLite3::ConstraintException if `url` is already present.
  def add(url:, title: nil, fetch_interval_seconds: PUBLISHER_INTERVAL)
    db.execute(<<~SQL, [url, title, fetch_interval_seconds])
      INSERT INTO feeds(url, title, fetch_interval_seconds) VALUES (?, ?, ?)
    SQL
    find(db.last_insert_row_id)
  end

  # Update arbitrary columns on an existing feed. Used by the fetch
  # pipeline to record etag / last_modified / last_fetched_at after a
  # successful poll. Unknown keys are silently ignored.
  def update(id, **fields)
    allowed = %i[
      title fetch_interval_seconds image_url
      last_fetched_at last_etag last_modified last_status
    ]
    cols = fields.slice(*allowed)
    return find(id) if cols.empty?

    set     = cols.keys.map { |k| "#{k} = ?" }.join(', ')
    values  = cols.values + [id]
    db.execute("UPDATE feeds SET #{set} WHERE id = ?", values)
    find(id)
  end

  # Delete cascades to articles → read_state / summaries / article_tags
  # via the foreign-key chain in 001_init.sql. Returns true if a row
  # was deleted, false if no feed had that id.
  def remove(id)
    db.execute('DELETE FROM feeds WHERE id = ?', [id])
    db.changes.positive?
  end

  class << self
    private

    def db
      Database.connection
    end
  end
end
