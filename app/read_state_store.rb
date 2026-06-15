require_relative 'database'
require_relative 'cache'

# Wrapper around the `read_state` table. The table has one row per
# (user_id, article_id), but rows are lazily created — an article without
# a read_state row for a user is treated as { read: 0, bookmarked: 0,
# archived: 0, opened_at: nil } by .get and the LEFT-JOIN queries in
# ArticlesStore.
#
# Every method requires the calling user's id explicitly. Production
# routes pass current_user_id; scripts read it from ENV['USER_USERNAME']
# at boot; specs that exercise the store directly use UsersStore.find(1).
module ReadStateStore
  module_function

  def get(user_id, article_id)
    row = db.execute(
      'SELECT * FROM read_state WHERE user_id = ? AND article_id = ?',
      [user_id, article_id]
    ).first
    row || {
      'user_id'          => user_id,
      'article_id'       => article_id,
      'read'             => 0,
      'bookmarked'       => 0,
      'archived'         => 0,
      'feedback'         => 0,
      'passive_feedback' => 0,
      'opened_at'        => nil
    }
  end

  def opened!(user_id, article_id)
    upsert(user_id, article_id, read: true, opened_at: Time.now.utc.iso8601)
  end

  def mark_read(user_id, article_id, read: true)
    upsert(user_id, article_id, read: read)
  end

  def mark_bookmarked(user_id, article_id, value: true)
    upsert(user_id, article_id, bookmarked: value)
  end

  def mark_archived(user_id, article_id, value: true)
    upsert(user_id, article_id, archived: value)
  end

  FEEDBACK_VALUES = [-1, 0, 1].freeze
  def mark_feedback(user_id, article_id, value:)
    raise ArgumentError, "feedback must be -1, 0, or +1 (got #{value.inspect})" unless FEEDBACK_VALUES.include?(value)
    upsert(user_id, article_id, feedback: value)
  end

  def mark_passive_feedback(user_id, article_id, value:)
    raise ArgumentError, "passive_feedback must be -1, 0, or +1 (got #{value.inspect})" unless FEEDBACK_VALUES.include?(value)
    current = get(user_id, article_id)
    return current if current['feedback'].to_i != 0
    upsert(user_id, article_id, passive_feedback: value)
  end

  # Count of unread articles in the user's *subscribed* feeds. The
  # subscription EXISTS clause both fixes correctness (an unsubscribed
  # feed's articles aren't "your unread") and avoids a full Seq Scan of
  # the whole articles corpus — it bounds the count to the user's feeds.
  # Same scoping pattern as ArticlesStore.state_query.
  def unread_count(user_id)
    # Cached (60s) + busted on any read-state write below — this scans the
    # articles corpus and runs on the home page for every returning user.
    Cache.fetch("unread:v1:#{user_id}", ttl: 60) do
      db.execute(<<~SQL, [user_id, user_id]).first['c']
        SELECT COUNT(*) AS c
        FROM articles a
        LEFT JOIN read_state rs ON a.id = rs.article_id AND rs.user_id = ?
        WHERE COALESCE(rs.read, 0) = 0
          AND EXISTS (
            SELECT 1 FROM user_feed_subscriptions ufs
            WHERE ufs.user_id = ? AND ufs.feed_id = a.feed_id
          )
      SQL
    end
  end

  def bookmarked_count(user_id)
    db.execute(
      'SELECT COUNT(*) AS c FROM read_state WHERE user_id = ? AND bookmarked = 1',
      [user_id]
    ).first['c']
  end

  # STUFF.md #14 — has this user opened/bookmarked/archived/thumbed
  # anything yet?
  def any_activity?(user_id)
    !db.execute('SELECT 1 FROM read_state WHERE user_id = ? LIMIT 1', [user_id]).first.nil?
  end

  class << self
    private

    def upsert(user_id, article_id, read: nil, bookmarked: nil, archived: nil, feedback: nil, passive_feedback: nil, opened_at: nil)
      current = get(user_id, article_id)
      next_row = {
        read:             (read.nil?             ? current['read']             : (read       ? 1 : 0)),
        bookmarked:       (bookmarked.nil?       ? current['bookmarked']       : (bookmarked ? 1 : 0)),
        archived:         (archived.nil?         ? current['archived']         : (archived   ? 1 : 0)),
        feedback:         (feedback.nil?         ? current['feedback']         : feedback.to_i),
        passive_feedback: (passive_feedback.nil? ? current['passive_feedback'] : passive_feedback.to_i),
        opened_at:        (opened_at.nil?        ? current['opened_at']        : opened_at)
      }

      sql = <<~SQL
        INSERT INTO read_state(user_id, article_id, read, bookmarked, archived, feedback, passive_feedback, opened_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (user_id, article_id) DO UPDATE SET
          read             = excluded.read,
          bookmarked       = excluded.bookmarked,
          archived         = excluded.archived,
          feedback         = excluded.feedback,
          passive_feedback = excluded.passive_feedback,
          opened_at        = excluded.opened_at
      SQL
      db.execute(sql, [
        user_id, article_id, next_row[:read], next_row[:bookmarked],
        next_row[:archived], next_row[:feedback], next_row[:passive_feedback], next_row[:opened_at]
      ])
      # A read-state change can move the unread count — bust its cache.
      Cache.delete("unread:v1:#{user_id}")
      get(user_id, article_id)
    end

    def db
      Database.connection
    end
  end
end
