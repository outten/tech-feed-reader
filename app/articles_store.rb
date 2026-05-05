require_relative 'database'
require_relative 'tags_store'
require_relative 'tags_applier'
require_relative 'summary_store'
require_relative 'summarizer/extractive'
require_relative 'providers/readability'
require_relative 'metrics'

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

  # Articles per published-day for the last N days, gap-filled to zero
  # so the chart has a stable x-axis. Returns [{day:, count:}] in
  # chronological order.
  def daily_counts(days: 30)
    today  = Date.today
    cutoff = (today - days + 1).to_s
    rows = db.execute(<<~SQL, [cutoff]).each_with_object({}) { |r, h| h[r['day']] = r['c'] }
      SELECT DATE(published_at) AS day, COUNT(*) AS c
      FROM articles
      WHERE DATE(published_at) >= ?
      GROUP BY DATE(published_at)
    SQL

    (0...days).map do |i|
      day = (today - (days - 1 - i)).to_s
      { day: day, count: rows[day] || 0 }
    end
  end

  # Top N feeds by total article count. Used by the /dashboard "Most
  # active feeds" widget. LEFT JOIN so feeds with zero articles still
  # show, but they sort to the bottom.
  def counts_by_feed(limit: 10)
    db.execute(<<~SQL, [limit])
      SELECT f.id, f.title, f.url, COUNT(a.id) AS c
      FROM feeds f
      LEFT JOIN articles a ON a.feed_id = f.id
      GROUP BY f.id
      ORDER BY c DESC, f.title ASC
      LIMIT ?
    SQL
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
  # for only the rows they want without re-issuing the query. `kind:`
  # narrows to :podcast (audio_url IS NOT NULL) when wanted.
  # max_duration_seconds, when set, bounds the query to articles whose
  # audio_duration_seconds is non-NULL and ≤ the given threshold —
  # used by /bus ("what's short enough for my commute?").
  def recent(limit: DEFAULT_LIMIT, offset: 0, state: :all, kind: :all, max_duration_seconds: nil)
    sql = state_query(filter: state, kind: kind, max_duration_seconds: max_duration_seconds)
    db.execute(sql, [limit, offset])
  end

  def for_feed(feed_id, limit: DEFAULT_LIMIT, offset: 0, state: :all)
    db.execute(state_query(scope: 'a.feed_id = ?', filter: state), [feed_id, limit, offset])
  end

  # Distinct feeds whose imported articles include at least one audio
  # enclosure — i.e. the user's subscribed podcasts. Used by /podcasts
  # to build the show grouping. Returns hash-rows with episode counts
  # and the most-recent published_at so the view can surface "freshest
  # show first" ordering.
  def podcast_feeds
    db.execute(<<~SQL)
      SELECT f.id, f.title, f.url, f.image_url,
             COUNT(a.id)         AS episode_count,
             MAX(a.published_at) AS latest_at
      FROM feeds f
      JOIN articles a ON a.feed_id = f.id
      WHERE a.audio_url IS NOT NULL
      GROUP BY f.id
      ORDER BY latest_at DESC NULLS LAST, f.title ASC
    SQL
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

  # Articles matching an FTS5 term, with their cached extractive
  # summaries inline (`summary` column) so the /topics/:term view can
  # render a "highlights" panel without a follow-up SummaryStore loop.
  # Ordered by FTS5 BM25 rank (most relevant first). Returns [] for
  # blank input or on FTS5 query syntax errors — same fallthrough as
  # ArticlesStore.search.
  def for_topic(term, limit: 30)
    return [] if term.to_s.strip.empty?
    db.execute(<<~SQL, [term.to_s.strip, limit])
      SELECT a.*, s.extractive AS summary, rank
      FROM articles a
      JOIN articles_fts f ON a.id = f.rowid
      LEFT JOIN summaries s ON s.article_id = a.id
      WHERE articles_fts MATCH ?
      ORDER BY rank
      LIMIT ?
    SQL
  rescue SQLite3::SQLException
    []
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
        (uid, feed_id, title, url, author, published_at, content_html, content_text,
         audio_url, audio_mime_type, audio_duration_seconds, image_url)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    SQL

    rules    = TagsStore.all  # snapshot once per import batch
    inserted = 0
    # Run readability OUTSIDE the transaction — readability does HTTP, and
    # we don't want the SQLite write lock held for the full duration of N
    # sequential publisher fetches. By the time we open the transaction
    # below every entry is already final.
    upgraded = entries.map { |e| maybe_readability_upgrade(e) }

    db.transaction do
      upgraded.each do |entry|
        db.execute(sql, [
          entry[:uid], feed_id,
          entry[:title].to_s, entry[:url].to_s,
          entry[:author], entry[:published_at],
          entry[:content_html].to_s, entry[:content_text].to_s,
          entry[:audio_url], entry[:audio_mime_type], entry[:audio_duration_seconds],
          entry[:image_url]
        ])
        next if db.changes.zero?  # uid was a duplicate, skip tag + summary

        inserted  += 1
        article_id = db.last_insert_row_id
        apply_tags_for(article_id, entry, feed_id, rules)
        generate_extractive_for(article_id, entry)
      end
    end
    Metrics::ARTICLES_IMPORTED.increment(by: inserted) if inserted.positive?
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

    # Auto-generate the extractive summary at import time. Pure-compute
    # (no network), so it stays inside the import transaction. Skips if
    # the body is empty so we don't store empty rows.
    def generate_extractive_for(article_id, entry)
      body = entry[:content_text].to_s.strip
      return if body.empty?
      summary = Summarizer::Extractive.summarize(body)
      return if summary.empty?
      SummaryStore.upsert(article_id, extractive: summary)
      Metrics::SUMMARIES_GENERATED.increment(labels: { kind: 'extractive' })
    end

    # When a feed body looks like a teaser (Lobsters / HN "Comments"
    # link, ≤300 chars), fetch the entry's source URL and run our
    # Readability extractor. On success, splice the extracted html /
    # text into the entry hash and continue the import. On failure,
    # the entry is returned unchanged — the user gets a placeholder
    # body but no crash.
    def maybe_readability_upgrade(entry)
      return entry unless Providers::Readability.teaser?(entry[:content_text])
      return entry if entry[:url].to_s.empty?

      upgrade = Providers::Readability.extract(entry[:url])
      return entry unless upgrade

      entry.merge(content_html: upgrade[:html], content_text: upgrade[:text])
    end

    # Build a SELECT a.*, read_state... over articles LEFT JOIN read_state
    # with optional WHERE-scope (e.g. "a.feed_id = ?"), an optional extra
    # FROM-clause join (used by for_tag), a read-state filter, and an
    # article-kind filter (:podcast → audio_url IS NOT NULL).
    def state_query(scope: nil, filter: :all, from_extra: nil, kind: :all, max_duration_seconds: nil)
      where_clauses = []
      where_clauses << scope if scope
      case filter
      when :unread     then where_clauses << 'COALESCE(rs.read, 0) = 0'
      when :bookmarked then where_clauses << 'rs.bookmarked = 1'
      when :archived   then where_clauses << 'rs.archived = 1'
      when :all        then # no extra clause
      else raise ArgumentError, "Unknown read-state filter: #{filter.inspect}"
      end
      case kind
      when :podcast then where_clauses << 'a.audio_url IS NOT NULL'
      when :all     then # no extra clause
      else raise ArgumentError, "Unknown kind filter: #{kind.inspect}"
      end
      if max_duration_seconds
        # Inlined as a number, not a placeholder, so the existing
        # callers' [limit, offset] / [feed_id, limit, offset] arg
        # arrays don't have to grow. Coerced to integer to keep the
        # SQL safe even if a string sneaks in.
        cutoff = Integer(max_duration_seconds)
        where_clauses << "a.audio_duration_seconds IS NOT NULL AND a.audio_duration_seconds <= #{cutoff}"
      end

      where_sql = where_clauses.empty? ? '' : "WHERE #{where_clauses.join(' AND ')}"

      <<~SQL
        SELECT a.*,
               COALESCE(rs.read, 0)       AS read,
               COALESCE(rs.bookmarked, 0) AS bookmarked,
               COALESCE(rs.archived, 0)   AS archived,
               COALESCE(rs.feedback, 0)   AS feedback,
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
