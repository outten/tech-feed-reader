require_relative 'database'
require_relative 'tags_store'
require_relative 'tags_applier'
require_relative 'summary_store'
require_relative 'summarizer/extractive'
require_relative 'providers/readability'
require_relative 'metrics'

# Wrapper around the `articles` table. Returns hash-rows so callers
# can pass them straight into ERB.
#
# Schema in db/migrations-postgres/001_init.sql. Full-text search hits
# the generated `tsv` tsvector column via ts_rank / ts_headline.
module ArticlesStore
  # Default page size for /articles. Tunable in views if needed.
  DEFAULT_LIMIT = 50

  module_function

  # Total articles in the catalog. Returns the global count; views that
  # care about a single user's reach call #count_for_user instead.
  def count
    db.execute('SELECT COUNT(*) AS c FROM articles').first['c']
  end

  def count_for_user(user_id)
    db.execute(<<~SQL, [user_id.to_i]).first['c']
      SELECT COUNT(*) AS c
      FROM articles a
      WHERE EXISTS (
        SELECT 1 FROM user_feed_subscriptions ufs
        WHERE ufs.user_id = ? AND ufs.feed_id = a.feed_id
      )
    SQL
  end

  # Articles per published-day for the last N days, scoped to the user's
  # subscriptions. Gap-filled to zero so the chart has a stable x-axis.
  def daily_counts(user_id, days: 30)
    today  = Date.today
    cutoff = (today - days + 1).to_s
    date_expr = Database.date_sql('a.published_at')
    rows = db.execute(<<~SQL, [user_id.to_i, cutoff]).each_with_object({}) { |r, h| h[r['day'].to_s] = r['c'] }
      SELECT #{date_expr} AS day, COUNT(*) AS c
      FROM articles a
      WHERE EXISTS (
        SELECT 1 FROM user_feed_subscriptions ufs
        WHERE ufs.user_id = ? AND ufs.feed_id = a.feed_id
      )
      AND #{date_expr} >= ?
      GROUP BY #{date_expr}
    SQL

    (0...days).map do |i|
      day = (today - (days - 1 - i)).to_s
      { day: day, count: rows[day] || 0 }
    end
  end

  # Top N feeds (within the user's subscriptions) by article count.
  def counts_by_feed(user_id, limit: 10)
    db.execute(<<~SQL, [user_id.to_i, limit])
      SELECT f.id, f.title, f.url, COUNT(a.id) AS c
      FROM feeds f
      JOIN user_feed_subscriptions ufs ON ufs.feed_id = f.id AND ufs.user_id = ?
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
  def recent(user_id, limit: DEFAULT_LIMIT, offset: 0, state: :all, kind: :all, max_duration_seconds: nil, topic: nil)
    sql, args = state_query(user_id: user_id, filter: state, kind: kind, max_duration_seconds: max_duration_seconds, topic: topic)
    db.execute(sql, args + [limit, offset])
  end

  def for_feed(user_id, feed_id, limit: DEFAULT_LIMIT, offset: 0, state: :all)
    sql, qargs = state_query(user_id: user_id, scope: 'a.feed_id = ?', scope_arg: feed_id, filter: state)
    db.execute(sql, qargs + [limit, offset])
  end

  # STUFF.md #109 — "I Feel Lucky": random cross-type sample from the
  # user's subscriptions. Respects mute rules; no other filters.
  #
  # Two-step approach: fetch subscribed feed IDs first so the planner sees
  # a literal IN list and uses idx_articles_feed_id (Bitmap Index Scan)
  # rather than a full table Seq Scan. Reduces the ORDER BY RANDOM() sort
  # from ~28K rows to ~2K rows when the user has many subscriptions.
  def random(user_id, limit: 50)
    uid = user_id.to_i
    feed_ids = db.execute('SELECT feed_id FROM user_feed_subscriptions WHERE user_id = ?', [uid])
                 .map { |r| r['feed_id'].to_i }
    return [] if feed_ids.empty?

    db.execute(<<~SQL, [uid, uid, limit])
      SELECT a.*,
             COALESCE(rs.read, 0)       AS read,
             COALESCE(rs.bookmarked, 0) AS bookmarked,
             COALESCE(rs.archived, 0)   AS archived,
             COALESCE(rs.feedback, 0)   AS feedback,
             rs.opened_at               AS opened_at
      FROM articles a
      LEFT JOIN read_state rs ON a.id = rs.article_id AND rs.user_id = ?
      WHERE a.feed_id IN (#{feed_ids.join(',')})
        AND NOT EXISTS (
              SELECT 1 FROM mute_rules mr
              WHERE mr.user_id = ? AND (
                  (mr.kind = 'keyword' AND (LOWER(a.title) LIKE '%' || LOWER(mr.value) || '%' OR LOWER(a.content_text) LIKE '%' || LOWER(mr.value) || '%'))
               OR (mr.kind = 'author'  AND a.author = mr.value)
               OR (mr.kind = 'feed'    AND a.feed_id = CAST(mr.value AS INTEGER))
              )
            )
      ORDER BY RANDOM()
      LIMIT ?
    SQL
  end

  # Distinct feeds (within the user's subscriptions) whose imported
  # articles include at least one audio enclosure. Used by /podcasts.
  def podcast_feeds(user_id)
    db.execute(<<~SQL, [user_id.to_i])
      SELECT f.id, f.title, f.url, f.image_url,
             COUNT(a.id)         AS episode_count,
             MAX(a.published_at) AS latest_at
      FROM feeds f
      JOIN user_feed_subscriptions ufs ON ufs.feed_id = f.id AND ufs.user_id = ?
      JOIN articles a ON a.feed_id = f.id
      WHERE a.audio_url IS NOT NULL
      GROUP BY f.id
      ORDER BY latest_at DESC NULLS LAST, f.title ASC
    SQL
  end

  # STUFF #26 — distinct YouTube channel feeds in the user's
  # subscriptions. Matched by the canonical YouTube channel-feed URL
  # pattern (https://www.youtube.com/feeds/videos.xml?channel_id=UC…),
  # which is the only stable signal we have today; storing a kind
  # column on feeds is a future-cleanup.
  YOUTUBE_FEED_URL_PATTERN = '%youtube.com/feeds/videos.xml%'.freeze

  def youtube_channels(user_id)
    # STUFF #50 — also return the latest video's uid + url so /youtube
    # can link channel cards directly to the most-recent episode.
    db.execute(<<~SQL, [user_id.to_i, YOUTUBE_FEED_URL_PATTERN])
      SELECT f.id, f.title, f.url, f.image_url,
             COUNT(a.id)         AS video_count,
             MAX(a.published_at) AS latest_at,
             (SELECT uid FROM articles
                WHERE feed_id = f.id
                ORDER BY published_at DESC NULLS LAST, id DESC
                LIMIT 1) AS latest_uid,
             (SELECT url FROM articles
                WHERE feed_id = f.id
                ORDER BY published_at DESC NULLS LAST, id DESC
                LIMIT 1) AS latest_url
      FROM feeds f
      JOIN user_feed_subscriptions ufs ON ufs.feed_id = f.id AND ufs.user_id = ?
      LEFT JOIN articles a ON a.feed_id = f.id
      WHERE f.url LIKE ?
      GROUP BY f.id
      ORDER BY latest_at DESC NULLS LAST, f.title ASC
    SQL
  end

  def latest_youtube_videos_for_channels(user_id, exclude_feed_ids: [])
    exclude_clause = exclude_feed_ids.empty? ? '' : "AND f.id NOT IN (#{exclude_feed_ids.map(&:to_i).join(',')})"
    db.execute(<<~SQL, [user_id.to_i, YOUTUBE_FEED_URL_PATTERN])
      SELECT DISTINCT ON (f.id)
             a.id, a.uid, a.title, a.url, a.published_at,
             a.feed_id, a.audio_url, a.content_text
      FROM articles a
      JOIN feeds f ON f.id = a.feed_id
      JOIN user_feed_subscriptions ufs ON ufs.feed_id = f.id AND ufs.user_id = ?
      WHERE f.url LIKE ?
        #{exclude_clause}
        AND (a.url LIKE '%youtube.com%' OR a.url LIKE '%youtu.be%')
      ORDER BY f.id, a.published_at DESC NULLS LAST, a.id DESC
    SQL
  end

  # STUFF #65 — distinct webcomic feeds in the user's subscriptions.
  # Matched by `feeds.topic = 'humor'` (the catalog-add path plumbs the
  # category's topic through). Returns the latest article's uid + its
  # panel image_url so /comics can render a tile per series with the
  # most-recent panel as the cover. Falls back to the feed's own
  # image_url when the latest article has no inline panel image.
  def comic_feeds(user_id)
    db.execute(<<~SQL, [user_id.to_i])
      SELECT f.id, f.title, f.url, f.image_url,
             COUNT(a.id)         AS panel_count,
             MAX(a.published_at) AS latest_at,
             (SELECT uid FROM articles
                WHERE feed_id = f.id
                ORDER BY published_at DESC NULLS LAST, id DESC
                LIMIT 1) AS latest_uid,
             (SELECT image_url FROM articles
                WHERE feed_id = f.id AND image_url IS NOT NULL
                ORDER BY published_at DESC NULLS LAST, id DESC
                LIMIT 1) AS latest_image
      FROM feeds f
      JOIN user_feed_subscriptions ufs ON ufs.feed_id = f.id AND ufs.user_id = ?
      LEFT JOIN articles a ON a.feed_id = f.id
      WHERE f.topic = 'humor'
      GROUP BY f.id
      ORDER BY latest_at DESC NULLS LAST, f.title ASC
    SQL
  end

  # Most recent N articles for one feed_id, joined with read_state for
  # the user — used by /youtube/:feed_id to render the recent-videos
  # grid. Doesn't go through state_query because we don't need the
  # subscription / mute-rule filters here (a single-feed view shows
  # whatever's there, even muted-author items).
  def recent_for_feed(user_id, feed_id, limit: 10)
    db.execute(<<~SQL, [user_id.to_i, feed_id.to_i, limit])
      SELECT a.*,
             COALESCE(rs.read, 0)       AS read,
             COALESCE(rs.bookmarked, 0) AS bookmarked,
             rs.opened_at               AS opened_at
      FROM articles a
      LEFT JOIN read_state rs ON a.id = rs.article_id AND rs.user_id = ?
      WHERE a.feed_id = ?
      ORDER BY a.published_at DESC, a.id DESC
      LIMIT ?
    SQL
  end

  # Re-hydrate full article rows (+ this user's read state) for a set of
  # ids, subscription-scoped and with an optional fresh state filter.
  # Used by the For-You ranker to materialize a cached ranking: the
  # cached id-list carries the ordering; this fetches the rows with
  # CURRENT read/bookmark state and drops anything the user has since
  # unsubscribed from or (for state: :unread) read. Order is NOT
  # guaranteed — the caller re-orders by the cached id-list.
  def by_ids_for_user(user_id, ids, state: :all)
    ids = Array(ids).map(&:to_i).uniq
    return [] if ids.empty?
    uid = user_id.to_i
    placeholders = (['?'] * ids.length).join(', ')
    state_clause = case state
                   when :unread     then 'AND COALESCE(rs.read, 0) = 0'
                   when :bookmarked then 'AND rs.bookmarked = 1'
                   when :archived   then 'AND rs.archived = 1'
                   when :all        then ''
                   else raise ArgumentError, "Unknown state filter: #{state.inspect}"
                   end
    db.execute(<<~SQL, [uid] + ids + [uid])
      SELECT a.*,
             COALESCE(rs.read, 0)       AS read,
             COALESCE(rs.bookmarked, 0) AS bookmarked,
             COALESCE(rs.archived, 0)   AS archived,
             COALESCE(rs.feedback, 0)   AS feedback,
             rs.opened_at               AS opened_at
      FROM articles a
      LEFT JOIN read_state rs ON a.id = rs.article_id AND rs.user_id = ?
      WHERE a.id IN (#{placeholders})
        AND EXISTS (
          SELECT 1 FROM user_feed_subscriptions ufs
          WHERE ufs.user_id = ? AND ufs.feed_id = a.feed_id
        )
        #{state_clause}
    SQL
  end

  # Articles tagged with the given tag id, scoped to the user.
  def for_tag(user_id, tag_id, limit: DEFAULT_LIMIT, offset: 0, state: :all)
    sql, qargs = state_query(
      user_id:    user_id,
      from_extra: 'JOIN article_tags at ON at.article_id = a.id',
      scope:      'at.tag_id = ?',
      scope_arg:  tag_id,
      filter:     state
    )
    db.execute(sql, qargs + [limit, offset])
  end

  # FTS hits filtered to the user's subscriptions, with cached
  # extractive summaries inline. Uses the generated `tsv` tsvector
  # column on articles + ts_rank.
  def for_topic(user_id, term, limit: 30)
    return [] if term.to_s.strip.empty?
    q = term.to_s.strip
    db.execute(<<~SQL, [q, q, user_id.to_i, limit])
      SELECT a.*, s.extractive AS summary,
             ts_rank(a.tsv, plainto_tsquery('english', ?)) AS rank
      FROM articles a
      LEFT JOIN summaries s ON s.article_id = a.id
      WHERE a.tsv @@ plainto_tsquery('english', ?)
        AND EXISTS (
          SELECT 1 FROM user_feed_subscriptions ufs
          WHERE ufs.user_id = ? AND ufs.feed_id = a.feed_id
        )
      ORDER BY rank DESC
      LIMIT ?
    SQL
  rescue PG::Error
    []
  end

  # Full-text search filtered to the user's subscriptions. Snippet is
  # generated server-side so the view can render `<mark>`-wrapped
  # excerpts uniformly.
  def search(user_id, query, limit: DEFAULT_LIMIT, offset: 0)
    return [] if query.to_s.strip.empty?
    q = query.to_s.strip

    db.execute(<<~SQL, [q, q, q, user_id.to_i, limit, offset])
      SELECT a.*,
             ts_headline('english', a.content_text,
                         plainto_tsquery('english', ?),
                         'StartSel=<mark>, StopSel=</mark>, MaxWords=16, MinWords=8') AS excerpt,
             ts_rank(a.tsv, plainto_tsquery('english', ?)) AS rank
      FROM articles a
      WHERE a.tsv @@ plainto_tsquery('english', ?)
        AND EXISTS (
          SELECT 1 FROM user_feed_subscriptions ufs
          WHERE ufs.user_id = ? AND ufs.feed_id = a.feed_id
        )
      ORDER BY rank DESC
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
      INSERT INTO articles
        (uid, feed_id, title, url, author, published_at, content_html, content_text,
         audio_url, audio_mime_type, audio_duration_seconds, image_url, categories,
         content_scrubbed)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, TRUE)
      ON CONFLICT DO NOTHING
    SQL

    # STUFF #28 — when a duplicate uid causes the INSERT to no-op, fill
    # in `categories` if the existing row's column is still NULL (i.e.
    # the article was imported before #28 shipped). All other columns
    # stay untouched. This piggybacks the regular sync-feeds cycle to
    # backfill the corpus naturally over the next 24h.
    backfill_sql = <<~SQL
      UPDATE articles SET categories = ? WHERE uid = ? AND categories IS NULL
    SQL

    # Cross-user tag snapshot — at import time we apply every user's
    # tag rules so the bridge (article_tags) is populated for all of
    # them. tag_id implicitly carries its owning user via tags.user_id.
    rules    = TagsStore.all_across_users
    inserted = 0
    # Run readability OUTSIDE the transaction — readability does HTTP, and
    # we don't want the DB write lock held for the full duration of N
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
          entry[:image_url], entry[:categories]
        ])
        if db.changes.zero?
          # uid was a duplicate — opportunistically backfill categories
          # if we have a value and the existing row doesn't.
          db.execute(backfill_sql, [entry[:categories], entry[:uid]]) if entry[:categories]
          next
        end

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
    # FROM-clause join (used by for_tag), a read-state filter, an
    # article-kind filter (:podcast → audio_url IS NOT NULL), and the
    # mandatory user_id scoping that excludes articles outside the user's
    # subscriptions / hides their muted authors+keywords / and joins
    # read_state to the calling user.
    #
    # Returns [sql, args]. `args` is the full param list in placeholder
    # order; callers append [limit, offset]. `scope_arg` is templated
    # into the args list at the right spot so callers don't have to
    # interleave manually.
    def state_query(user_id:, scope: nil, scope_arg: nil, filter: :all, from_extra: nil, kind: :all, max_duration_seconds: nil, topic: nil)
      uid = user_id.to_i
      where_clauses = []
      args = []

      # Subscription scope — every list view filters to articles whose
      # feed the user is subscribed to. No-op for users subscribed to
      # everything (e.g. t-money post-A2 migration).
      where_clauses << <<~SQL.strip
        EXISTS (
          SELECT 1 FROM user_feed_subscriptions ufs
          WHERE ufs.user_id = ? AND ufs.feed_id = a.feed_id
        )
      SQL
      args << uid

      if scope
        where_clauses << scope
        args << scope_arg unless scope_arg.nil?
      end

      case filter
      when :unread     then where_clauses << 'COALESCE(rs.read, 0) = 0'
      when :bookmarked then where_clauses << 'rs.bookmarked = 1'
      when :archived   then where_clauses << 'rs.archived = 1'
      when :all        then # no extra clause
      else raise ArgumentError, "Unknown read-state filter: #{filter.inspect}"
      end

      case kind
      when :podcast then where_clauses << 'a.audio_url IS NOT NULL'
      when :youtube then where_clauses << "EXISTS (SELECT 1 FROM feeds f WHERE f.id = a.feed_id AND f.url LIKE '%youtube.com/feeds/videos.xml%')"
      when :all     then # no extra clause
      else raise ArgumentError, "Unknown kind filter: #{kind.inspect}"
      end

      if max_duration_seconds
        cutoff = Integer(max_duration_seconds)
        where_clauses << "a.audio_duration_seconds IS NOT NULL AND a.audio_duration_seconds <= #{cutoff}"
      end

      if topic
        where_clauses << 'EXISTS (SELECT 1 FROM feeds f WHERE f.id = a.feed_id AND f.topic = ?)'
        args << topic.to_s
      end

      # Phase 5 — hide articles matching the user's mute_rules.
      where_clauses << <<~SQL.strip
        NOT EXISTS (
          SELECT 1 FROM mute_rules mr
          WHERE mr.user_id = ? AND (
              (mr.kind = 'keyword' AND (LOWER(a.title) LIKE '%' || LOWER(mr.value) || '%' OR LOWER(a.content_text) LIKE '%' || LOWER(mr.value) || '%'))
           OR (mr.kind = 'author'  AND a.author = mr.value)
           OR (mr.kind = 'feed'    AND a.feed_id = CAST(mr.value AS INTEGER))
          )
        )
      SQL
      args << uid

      sql = <<~SQL
        SELECT a.*,
               COALESCE(rs.read, 0)       AS read,
               COALESCE(rs.bookmarked, 0) AS bookmarked,
               COALESCE(rs.archived, 0)   AS archived,
               COALESCE(rs.feedback, 0)   AS feedback,
               rs.opened_at               AS opened_at
        FROM articles a
        LEFT JOIN read_state rs ON a.id = rs.article_id AND rs.user_id = ?
        #{from_extra}
        WHERE #{where_clauses.join(' AND ')}
        ORDER BY a.published_at DESC, a.id DESC
        LIMIT ? OFFSET ?
      SQL
      # rs.user_id placeholder lives at the very front of args (it's in
      # the LEFT JOIN, which runs before WHERE).
      [sql, [uid] + args]
    end

    def db
      Database.connection
    end
  end
end
