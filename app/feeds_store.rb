require_relative 'database'

# Wrapper around the `feeds` (shared catalog) + `user_feed_subscriptions`
# (per-user) tables.
#
# A2 model: `feeds` is a global catalog so one fetch keeps every
# subscriber up to date. `user_feed_subscriptions` bridges users to the
# feeds they care about. Routes work in terms of "this user's
# subscriptions"; the fetcher walks `feeds` directly.
module FeedsStore
  HIGH_FREQUENCY_INTERVAL = 15 * 60       # 15 min
  PUBLISHER_INTERVAL      = 60 * 60       # 1 h
  PERSONAL_BLOG_INTERVAL  = 4 * 60 * 60   # 4 h

  module_function

  # ---- catalog (cross-user) -------------------------------------------

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

  # Fetcher entry point — every feed in the catalog, regardless of
  # subscribers. Alias of #all but named so the intent is clear at the
  # call site.
  def all_for_fetch
    all
  end

  # Test + script convenience: insert into the catalog AND subscribe
  # `subscriber_id` (defaults to 1, the seeded test user). Preserves
  # the pre-A2 contract of raising SQLite3::ConstraintException on a
  # duplicate URL so existing specs keep passing. Production routes
  # call #add_for_user(user_id:, ...) instead.
  def add(url:, title: nil, fetch_interval_seconds: PUBLISHER_INTERVAL, topic: 'general', subscriber_id: 1)
    raise SQLite3::ConstraintException, "UNIQUE constraint failed: feeds.url" if find_by_url(url)
    feed = add_to_catalog(
      url: url, title: title,
      fetch_interval_seconds: fetch_interval_seconds,
      topic: topic
    )
    subscribe(subscriber_id, feed['id'])
    feed
  end

  # Insert a feed into the shared catalog. Idempotent via the url unique
  # index — re-adding the same URL returns the existing row. Raises
  # only if the schema is wrong.
  def add_to_catalog(url:, title: nil, fetch_interval_seconds: PUBLISHER_INTERVAL, topic: 'general')
    existing = find_by_url(url)
    return existing if existing

    db.execute(<<~SQL, [url, title, fetch_interval_seconds, topic.to_s])
      INSERT INTO feeds(url, title, fetch_interval_seconds, topic) VALUES (?, ?, ?, ?)
    SQL
    find(db.last_insert_row_id)
  end

  # Updates whitelisted catalog fields (used by the fetch pipeline to
  # record etag / last_modified / last_fetched_at).
  def update(id, **fields)
    allowed = %i[
      title fetch_interval_seconds image_url topic
      last_fetched_at last_etag last_modified last_status
    ]
    cols = fields.slice(*allowed)
    return find(id) if cols.empty?

    set     = cols.keys.map { |k| "#{k} = ?" }.join(', ')
    values  = cols.values + [id]
    db.execute("UPDATE feeds SET #{set} WHERE id = ?", values)
    find(id)
  end

  # Delete from the catalog (NOT a user-facing operation any more — see
  # #unsubscribe). Cascades to articles → read_state / summaries / etc.
  # via the FK chain. Kept for admin scripts / tests.
  def remove(id)
    db.execute('DELETE FROM feeds WHERE id = ?', [id])
    db.changes.positive?
  end

  # ---- per-user subscriptions -----------------------------------------

  # All feed rows the user is subscribed to, in catalog-stable order.
  def for_user(user_id)
    db.execute(<<~SQL, [user_id.to_i])
      SELECT f.*
      FROM feeds f
      JOIN user_feed_subscriptions ufs ON ufs.feed_id = f.id
      WHERE ufs.user_id = ?
      ORDER BY f.id ASC
    SQL
  end

  def count_for_user(user_id)
    db.execute(
      'SELECT COUNT(*) AS c FROM user_feed_subscriptions WHERE user_id = ?',
      [user_id.to_i]
    ).first['c']
  end

  def subscribed?(user_id, feed_id)
    !db.execute(
      'SELECT 1 FROM user_feed_subscriptions WHERE user_id = ? AND feed_id = ? LIMIT 1',
      [user_id.to_i, feed_id.to_i]
    ).first.nil?
  end

  def subscribe(user_id, feed_id)
    db.execute(
      'INSERT OR IGNORE INTO user_feed_subscriptions(user_id, feed_id) VALUES (?, ?)',
      [user_id.to_i, feed_id.to_i]
    )
    db.changes.positive?
  end

  def unsubscribe(user_id, feed_id)
    db.execute(
      'DELETE FROM user_feed_subscriptions WHERE user_id = ? AND feed_id = ?',
      [user_id.to_i, feed_id.to_i]
    )
    db.changes.positive?
  end

  # Convenience used by the /feeds add form: insert into the catalog
  # (or find the existing row) and subscribe the user. Returns
  # [feed_row, was_new_for_user]: was_new_for_user=true means the user
  # didn't already have this feed.
  def add_for_user(user_id:, url:, title: nil, fetch_interval_seconds: PUBLISHER_INTERVAL, topic: 'general')
    feed = add_to_catalog(
      url: url,
      title: title,
      fetch_interval_seconds: fetch_interval_seconds,
      topic: topic
    )
    inserted = subscribe(user_id, feed['id'])
    [feed, inserted]
  end

  # ---- top charts (STUFF #24 — cross-user discovery) ------------------

  # Mirrors ArticlesStore::YOUTUBE_FEED_URL_PATTERN — kept local so the
  # store doesn't need to require articles_store just for this constant.
  YOUTUBE_FEED_URL_PATTERN = '%youtube.com/feeds/videos.xml%'.freeze

  POPULAR_TYPES = %w[news sports podcasts nature youtube].freeze
  POPULAR_TYPE_LABELS = {
    'news'     => '📰 News',
    'sports'   => '🏟 Sports',
    'podcasts' => '🎧 Podcasts',
    'nature'   => '📺 Nature',
    'youtube'  => '🎬 YouTube'
  }.freeze

  # Top feeds for one type, ranked by distinct subscriber count desc.
  # Today every feed has count=1 (single user); the chart goes live as
  # more users subscribe to overlapping feeds. Types are mutually
  # exclusive (a YouTube nature channel is in `youtube`, not `nature`).
  def popular_by_type(type, limit: 5)
    case type.to_s
    when 'youtube'  then popular_query("f.url LIKE ?",                              [YOUTUBE_FEED_URL_PATTERN], limit)
    when 'podcasts' then popular_query("f.url NOT LIKE ? AND f.id IN (SELECT feed_id FROM articles WHERE audio_url IS NOT NULL)",
                                      [YOUTUBE_FEED_URL_PATTERN], limit)
    when 'sports'   then popular_query("f.url NOT LIKE ? AND f.id NOT IN (SELECT feed_id FROM articles WHERE audio_url IS NOT NULL) AND f.topic = 'sports'",
                                      [YOUTUBE_FEED_URL_PATTERN], limit)
    when 'nature'   then popular_query("f.url NOT LIKE ? AND f.id NOT IN (SELECT feed_id FROM articles WHERE audio_url IS NOT NULL) AND f.topic = 'nature'",
                                      [YOUTUBE_FEED_URL_PATTERN], limit)
    when 'news'     then popular_query("f.url NOT LIKE ? AND f.id NOT IN (SELECT feed_id FROM articles WHERE audio_url IS NOT NULL) AND f.topic IN ('technology', 'general')",
                                      [YOUTUBE_FEED_URL_PATTERN], limit)
    else []
    end
  end

  class << self
    private

    def db
      Database.connection
    end

    def popular_query(where_clause, where_args, limit)
      db.execute(<<~SQL, where_args + [limit])
        SELECT f.id, f.url, f.title, f.image_url, f.topic,
               (SELECT COUNT(*) FROM user_feed_subscriptions WHERE feed_id = f.id) AS subscriber_count
        FROM feeds f
        WHERE #{where_clause}
        ORDER BY subscriber_count DESC, f.id ASC
        LIMIT ?
      SQL
    end
  end
end
