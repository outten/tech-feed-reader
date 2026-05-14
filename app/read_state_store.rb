require_relative 'database'

# Wrapper around the `read_state` table. The table has one row per
# (user_id, article_id), but rows are lazily created — an article without
# a read_state row for a user is treated as { read: 0, bookmarked: 0,
# archived: 0, opened_at: nil } by .get and the LEFT-JOIN queries in
# ArticlesStore.
#
# Every per-user method accepts (user_id, article_id) OR (article_id)
# alone — in the second form, user_id defaults to 1 (the seeded test
# user / single-user-mode owner). Production routes always pass an
# explicit current_user_id.
module ReadStateStore
  module_function

  def get(*args)
    user_id, article_id = args.length == 2 ? args : [1, args.first]
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

  def opened!(*args)
    user_id, article_id = args.length == 2 ? args : [1, args.first]
    upsert(user_id, article_id, read: true, opened_at: Time.now.utc.iso8601)
  end

  def mark_read(*args, read: true)
    user_id, article_id = args.length == 2 ? args : [1, args.first]
    upsert(user_id, article_id, read: read)
  end

  def mark_bookmarked(*args, value: true)
    user_id, article_id = args.length == 2 ? args : [1, args.first]
    upsert(user_id, article_id, bookmarked: value)
  end

  def mark_archived(*args, value: true)
    user_id, article_id = args.length == 2 ? args : [1, args.first]
    upsert(user_id, article_id, archived: value)
  end

  FEEDBACK_VALUES = [-1, 0, 1].freeze
  def mark_feedback(*args, value:)
    raise ArgumentError, "feedback must be -1, 0, or +1 (got #{value.inspect})" unless FEEDBACK_VALUES.include?(value)
    user_id, article_id = args.length == 2 ? args : [1, args.first]
    upsert(user_id, article_id, feedback: value)
  end

  def mark_passive_feedback(*args, value:)
    raise ArgumentError, "passive_feedback must be -1, 0, or +1 (got #{value.inspect})" unless FEEDBACK_VALUES.include?(value)
    user_id, article_id = args.length == 2 ? args : [1, args.first]
    current = get(user_id, article_id)
    return current if current['feedback'].to_i != 0
    upsert(user_id, article_id, passive_feedback: value)
  end

  def unread_count(user_id = 1)
    db.execute(<<~SQL, [user_id]).first['c']
      SELECT COUNT(*) AS c
      FROM articles a
      LEFT JOIN read_state rs ON a.id = rs.article_id AND rs.user_id = ?
      WHERE COALESCE(rs.read, 0) = 0
    SQL
  end

  def bookmarked_count(user_id = 1)
    db.execute(
      'SELECT COUNT(*) AS c FROM read_state WHERE user_id = ? AND bookmarked = 1',
      [user_id]
    ).first['c']
  end

  # STUFF.md #14 — has this user opened/bookmarked/archived/thumbed
  # anything yet?
  def any_activity?(user_id = 1)
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
        INSERT OR REPLACE INTO read_state(user_id, article_id, read, bookmarked, archived, feedback, passive_feedback, opened_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      db.execute(sql, [
        user_id, article_id, next_row[:read], next_row[:bookmarked],
        next_row[:archived], next_row[:feedback], next_row[:passive_feedback], next_row[:opened_at]
      ])
      get(user_id, article_id)
    end

    def db
      Database.connection
    end
  end
end
