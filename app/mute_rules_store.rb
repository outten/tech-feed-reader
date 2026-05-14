require_relative 'database'

# Phase 5 — per-user wrapper around mute_rules.
#
# Three kinds of rule, each with a different match shape:
#   keyword → substring match against title OR content_text (case-insensitive,
#             via SQLite's default ASCII-LIKE which already lower-cases)
#   author  → exact match against articles.author
#   feed    → match against articles.feed_id (value stored as the id-as-string)
#
# The matching itself lives in ArticlesStore.state_query as a single
# NOT EXISTS sub-query — see the rationale there.
module MuteRulesStore
  KINDS = %w[keyword author feed].freeze

  module_function

  def all(user_id)
    db.execute(
      'SELECT * FROM mute_rules WHERE user_id = ? ORDER BY kind, created_at DESC',
      [user_id.to_i]
    )
  end

  def for_kind(user_id, kind)
    raise ArgumentError, "unknown kind: #{kind.inspect}" unless KINDS.include?(kind.to_s)
    db.execute(
      'SELECT * FROM mute_rules WHERE user_id = ? AND kind = ? ORDER BY created_at DESC',
      [user_id.to_i, kind.to_s]
    )
  end

  def count(user_id)
    db.execute('SELECT COUNT(*) AS c FROM mute_rules WHERE user_id = ?', [user_id.to_i]).first['c']
  end

  # Idempotent — re-adding (user_id, kind, value) is a no-op because
  # (user_id, kind, value) is the natural key. Trims surrounding
  # whitespace on `value`. Returns true if a new row was inserted, false
  # if the rule already existed.
  def add(user_id:, kind:, value:)
    kind  = kind.to_s
    value = value.to_s.strip
    raise ArgumentError, "unknown kind: #{kind.inspect}" unless KINDS.include?(kind)
    raise ArgumentError, 'value must be non-empty'      if value.empty?

    db.execute(
      'INSERT OR IGNORE INTO mute_rules(user_id, kind, value) VALUES (?, ?, ?)',
      [user_id.to_i, kind, value]
    )
    db.changes.positive?
  end

  # Delete a rule. No-op if it doesn't exist. Returns the number of
  # rows actually removed (0 or 1).
  def remove(user_id:, kind:, value:)
    kind  = kind.to_s
    value = value.to_s.strip
    raise ArgumentError, "unknown kind: #{kind.inspect}" unless KINDS.include?(kind)

    db.execute(
      'DELETE FROM mute_rules WHERE user_id = ? AND kind = ? AND value = ?',
      [user_id.to_i, kind, value]
    )
    db.changes
  end

  class << self
    private

    def db
      Database.connection
    end
  end
end
