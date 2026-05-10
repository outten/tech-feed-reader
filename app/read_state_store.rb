require_relative 'database'

# Wrapper around the `read_state` table. The table has one row per
# article, but rows are lazily created — an article without a
# read_state row is treated as { read: 0, bookmarked: 0, archived: 0,
# opened_at: nil } by .get and the LEFT-JOIN queries in ArticlesStore.
#
# Toggle semantics: every mutator is idempotent. Calling .mark_read
# twice with the same value yields the same end state. INSERT OR
# REPLACE keeps the row count at 1 per article.
module ReadStateStore
  module_function

  # Returns the row hash, or a synthetic default if no row exists.
  # Use this when the caller needs concrete fields rather than knowing
  # whether the row was lazily created.
  def get(article_id)
    row = db.execute('SELECT * FROM read_state WHERE article_id = ?', [article_id]).first
    row || {
      'article_id'       => article_id,
      'read'             => 0,
      'bookmarked'       => 0,
      'archived'         => 0,
      'feedback'         => 0,
      'passive_feedback' => 0,
      'opened_at'        => nil
    }
  end

  # Mark the article as opened (sets opened_at to now and read=1).
  # Called from GET /article/:uid so visiting an article counts as
  # reading it — reversible via mark_read(article_id, read: false).
  def opened!(article_id)
    upsert(article_id, read: true, opened_at: Time.now.utc.iso8601)
  end

  def mark_read(article_id, read: true)
    upsert(article_id, read: read)
  end

  def mark_bookmarked(article_id, value: true)
    upsert(article_id, bookmarked: value)
  end

  def mark_archived(article_id, value: true)
    upsert(article_id, archived: value)
  end

  # Set per-article feedback (Phase 3 valence signal). Accepted values:
  #   +1 → thumbs up      (boost in the Phase 6 ranker)
  #   -1 → thumbs down    (demote)
  #    0 → cleared / unset (default state)
  # Toggle semantics: the route layer flips +1↔0 / -1↔0; this method
  # just persists whatever it's given. Out-of-range values raise so a
  # mistyped param doesn't silently corrupt data.
  FEEDBACK_VALUES = [-1, 0, 1].freeze
  def mark_feedback(article_id, value:)
    raise ArgumentError, "feedback must be -1, 0, or +1 (got #{value.inspect})" unless FEEDBACK_VALUES.include?(value)
    upsert(article_id, feedback: value)
  end

  # Phase 4 — passive valence signal derived from listened-percent on
  # podcast episodes. Same {-1, 0, +1} domain as #mark_feedback, but
  # explicit feedback always wins: if read_state.feedback is non-zero
  # we leave passive_feedback alone (returns the unchanged row). This
  # guard lives in the store rather than the route so any future
  # caller (cron, batch import) gets it for free.
  def mark_passive_feedback(article_id, value:)
    raise ArgumentError, "passive_feedback must be -1, 0, or +1 (got #{value.inspect})" unless FEEDBACK_VALUES.include?(value)
    current = get(article_id)
    return current if current['feedback'].to_i != 0
    upsert(article_id, passive_feedback: value)
  end

  def unread_count
    db.execute(<<~SQL).first['c']
      SELECT COUNT(*) AS c
      FROM articles a
      LEFT JOIN read_state rs ON a.id = rs.article_id
      WHERE COALESCE(rs.read, 0) = 0
    SQL
  end

  def bookmarked_count
    db.execute('SELECT COUNT(*) AS c FROM read_state WHERE bookmarked = 1').first['c']
  end

  # STUFF.md #14 — fast probe for "has the user actually used this app
  # at all?". Any read_state row means at least one article was opened,
  # bookmarked, archived, or thumbed. Used by GET / to switch the home
  # page from the marketing pitch to a personalized "Welcome back" hero.
  def any_activity?
    !db.execute('SELECT 1 FROM read_state LIMIT 1').first.nil?
  end

  class << self
    private

    # Single mutator under the hood. Reads the current row (or default),
    # overlays the requested fields, and writes back via INSERT OR
    # REPLACE so we don't need separate insert/update branches.
    def upsert(article_id, read: nil, bookmarked: nil, archived: nil, feedback: nil, passive_feedback: nil, opened_at: nil)
      current = get(article_id)
      next_row = {
        read:             (read.nil?             ? current['read']             : (read       ? 1 : 0)),
        bookmarked:       (bookmarked.nil?       ? current['bookmarked']       : (bookmarked ? 1 : 0)),
        archived:         (archived.nil?         ? current['archived']         : (archived   ? 1 : 0)),
        feedback:         (feedback.nil?         ? current['feedback']         : feedback.to_i),
        passive_feedback: (passive_feedback.nil? ? current['passive_feedback'] : passive_feedback.to_i),
        opened_at:        (opened_at.nil?        ? current['opened_at']        : opened_at)
      }

      sql = <<~SQL
        INSERT OR REPLACE INTO read_state(article_id, read, bookmarked, archived, feedback, passive_feedback, opened_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      SQL
      db.execute(sql, [
        article_id, next_row[:read], next_row[:bookmarked],
        next_row[:archived], next_row[:feedback], next_row[:passive_feedback], next_row[:opened_at]
      ])
      get(article_id)
    end

    def db
      Database.connection
    end
  end
end
