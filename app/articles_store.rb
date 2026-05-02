require_relative 'database'

# Wrapper around the `articles` table. Returns hash-rows (matching
# Database#results_as_hash) so callers can pass them straight into ERB.
#
# Schema in db/migrations/001_init.sql. The articles_fts virtual table
# is kept in sync via INSERT/UPDATE/DELETE triggers, so .import simply
# inserts and the index follows. Search hits articles_fts via JOIN on
# articles.id (the rowid the FTS5 contentless table is linked to).
module ArticlesStore
  # Default page size for /articles. Tunable in views if needed.
  DEFAULT_LIMIT = 50

  module_function

  def count
    db.execute('SELECT COUNT(*) AS c FROM articles').first['c']
  end

  def find(id)
    db.execute('SELECT * FROM articles WHERE id = ?', [id]).first
  end

  def find_by_uid(uid)
    db.execute('SELECT * FROM articles WHERE uid = ?', [uid]).first
  end

  # Most recent articles across all feeds. Ordered by published_at then
  # id so missing-published_at rows don't bunch at the top.
  def recent(limit: DEFAULT_LIMIT, offset: 0)
    db.execute(<<~SQL, [limit, offset])
      SELECT * FROM articles
      ORDER BY published_at DESC, id DESC
      LIMIT ? OFFSET ?
    SQL
  end

  def for_feed(feed_id, limit: DEFAULT_LIMIT, offset: 0)
    db.execute(<<~SQL, [feed_id, limit, offset])
      SELECT * FROM articles
      WHERE feed_id = ?
      ORDER BY published_at DESC, id DESC
      LIMIT ? OFFSET ?
    SQL
  end

  # Full-text search via the articles_fts virtual table. `rank` is FTS5's
  # built-in relevance score (lower = better). Empty / blank queries
  # return [] instead of raising — FTS5 errors on empty MATCH terms.
  def search(query, limit: DEFAULT_LIMIT)
    return [] if query.to_s.strip.empty?

    db.execute(<<~SQL, [query.to_s.strip, limit])
      SELECT a.*
      FROM articles a
      JOIN articles_fts f ON a.id = f.rowid
      WHERE articles_fts MATCH ?
      ORDER BY rank
      LIMIT ?
    SQL
  end

  # Bulk-insert a batch of FeedParser-shaped entries for a given feed.
  # Skips entries whose uid already exists (per AGENTS.md "for each
  # entry not already in articles by uid"); returns the count of new
  # rows actually inserted. The transaction wrap keeps a multi-entry
  # import atomic + fast.
  def import(feed_id:, entries:)
    return 0 if entries.empty?

    sql = <<~SQL
      INSERT OR IGNORE INTO articles
        (uid, feed_id, title, url, author, published_at, content_html, content_text)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    SQL

    inserted = 0
    db.transaction do
      entries.each do |entry|
        db.execute(sql, [
          entry[:uid], feed_id,
          entry[:title].to_s, entry[:url].to_s,
          entry[:author], entry[:published_at],
          entry[:content_html].to_s, entry[:content_text].to_s
        ])
        inserted += db.changes
      end
    end
    inserted
  end

  class << self
    private

    def db
      Database.connection
    end
  end
end
