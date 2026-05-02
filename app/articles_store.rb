require_relative 'database'
require_relative 'tags_store'
require_relative 'tags_applier'

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
  #
  # Returns rows with read / bookmarked / archived / opened_at columns
  # populated from a LEFT JOIN on read_state — so callers don't have to
  # follow up with a per-article ReadStateStore.get. Optional state:
  # filter (:unread | :bookmarked | :archived | :all) lets callers ask
  # for only the rows they want without re-issuing the query.
  def recent(limit: DEFAULT_LIMIT, offset: 0, state: :all)
    db.execute(state_query(filter: state), [limit, offset])
  end

  def for_feed(feed_id, limit: DEFAULT_LIMIT, offset: 0, state: :all)
    db.execute(state_query(scope: 'a.feed_id = ?', filter: state), [feed_id, limit, offset])
  end

  # Articles tagged with the given tag id, with read-state columns and
  # optional state filter. Joins article_tags inside the FROM clause
  # (vs. as a sub-select) so SQLite can use the article_tags PK index.
  def for_tag(tag_id, limit: DEFAULT_LIMIT, offset: 0, state: :all)
    sql = state_query(
      from_extra: 'JOIN article_tags at ON at.article_id = a.id',
      scope:      'at.tag_id = ?',
      filter:     state
    )
    db.execute(sql, [tag_id, limit, offset])
  end

  # Full-text search via the articles_fts virtual table. `rank` is FTS5's
  # built-in relevance score (lower = better). Empty / blank queries
  # return [] instead of raising — FTS5 errors on empty MATCH terms.
  #
  # Returned rows include an `excerpt` column built via FTS5's snippet()
  # function — content_text with up to 16 tokens around the match,
  # surrounded by <mark>…</mark> tags. Safe to render unescaped (the
  # underlying content_text was sanitized at import; snippet only adds
  # <mark> markers).
  #
  # Raises SQLite3::SQLException on a malformed FTS5 query (e.g. an
  # unmatched quote). Callers — currently the /search route — rescue
  # and surface the message to the user.
  def search(query, limit: DEFAULT_LIMIT, offset: 0)
    return [] if query.to_s.strip.empty?

    db.execute(<<~SQL, [query.to_s.strip, limit, offset])
      SELECT a.*,
             snippet(articles_fts, 1, '<mark>', '</mark>', '…', 16) AS excerpt
      FROM articles a
      JOIN articles_fts f ON a.id = f.rowid
      WHERE articles_fts MATCH ?
      ORDER BY rank
      LIMIT ? OFFSET ?
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

    rules    = TagsStore.all  # snapshot once per import batch
    inserted = 0
    db.transaction do
      entries.each do |entry|
        db.execute(sql, [
          entry[:uid], feed_id,
          entry[:title].to_s, entry[:url].to_s,
          entry[:author], entry[:published_at],
          entry[:content_html].to_s, entry[:content_text].to_s
        ])
        next if db.changes.zero?  # uid was a duplicate, skip tag step

        inserted  += 1
        article_id = db.last_insert_row_id
        apply_tags_for(article_id, entry, feed_id, rules)
      end
    end
    inserted
  end

  class << self
    private

    # Apply tag rules to a freshly-inserted article. Runs inside the
    # import transaction so the article + its tags land atomically.
    def apply_tags_for(article_id, entry, feed_id, rules)
      return if rules.empty?
      shape = {
        'title'        => entry[:title].to_s,
        'content_text' => entry[:content_text].to_s,
        'feed_id'      => feed_id
      }
      TagsApplier.matching_tag_ids(shape, rules).each do |tag_id|
        TagsStore.tag_article(article_id, tag_id)
      end
    end

    # Build a SELECT a.*, read_state... over articles LEFT JOIN read_state
    # with optional WHERE-scope (e.g. "a.feed_id = ?"), an optional extra
    # FROM-clause join (used by for_tag), and a read-state filter.
    def state_query(scope: nil, filter: :all, from_extra: nil)
      where_clauses = []
      where_clauses << scope if scope
      case filter
      when :unread     then where_clauses << 'COALESCE(rs.read, 0) = 0'
      when :bookmarked then where_clauses << 'rs.bookmarked = 1'
      when :archived   then where_clauses << 'rs.archived = 1'
      when :all        then # no extra clause
      else raise ArgumentError, "Unknown read-state filter: #{filter.inspect}"
      end

      where_sql = where_clauses.empty? ? '' : "WHERE #{where_clauses.join(' AND ')}"

      <<~SQL
        SELECT a.*,
               COALESCE(rs.read, 0)       AS read,
               COALESCE(rs.bookmarked, 0) AS bookmarked,
               COALESCE(rs.archived, 0)   AS archived,
               rs.opened_at               AS opened_at
        FROM articles a
        LEFT JOIN read_state rs ON a.id = rs.article_id
        #{from_extra}
        #{where_sql}
        ORDER BY a.published_at DESC, a.id DESC
        LIMIT ? OFFSET ?
      SQL
    end

    def db
      Database.connection
    end
  end
end
