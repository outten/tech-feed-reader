require_relative 'database'

# Phase 5 — wrapper around the mute_rules table.
#
# Three kinds of rule, each with a different match shape:
#   keyword → substring match against title OR content_text (case-insensitive,
#             via SQLite's default ASCII-LIKE which already lower-cases)
#   author  → exact match against articles.author
#   feed    → match against articles.feed_id (value stored as the id-as-string)
#
# The matching itself lives in ArticlesStore.state_query as a single
# NOT EXISTS sub-query — see the rationale there. This module is just
# CRUD + validation. The schema's CHECK constraint on `kind` is a
# belt-and-suspenders against a malformed row.
module MuteRulesStore
  KINDS = %w[keyword author feed].freeze

  module_function

  def all
    db.execute('SELECT * FROM mute_rules ORDER BY kind, created_at DESC')
  end

  def for_kind(kind)
    raise ArgumentError, "unknown kind: #{kind.inspect}" unless KINDS.include?(kind.to_s)
    db.execute('SELECT * FROM mute_rules WHERE kind = ? ORDER BY created_at DESC', [kind.to_s])
  end

  def count
    db.execute('SELECT COUNT(*) AS c FROM mute_rules').first['c']
  end

  # Insert a rule. Idempotent — re-adding (kind, value) is a no-op
  # because (kind, value) is the natural key. Trims surrounding
  # whitespace on `value` so "  Hacker News " and "Hacker News" don't
  # become two rules. Returns true if a new row was inserted, false
  # if the rule already existed.
  def add(kind:, value:)
    kind  = kind.to_s
    value = value.to_s.strip
    raise ArgumentError, "unknown kind: #{kind.inspect}" unless KINDS.include?(kind)
    raise ArgumentError, 'value must be non-empty'      if value.empty?

    db.execute('INSERT OR IGNORE INTO mute_rules(kind, value) VALUES (?, ?)', [kind, value])
    db.changes.positive?
  end

  # Delete a rule. No-op if it doesn't exist. Returns the number of
  # rows actually removed (0 or 1) so the caller can flash a useful
  # notice.
  def remove(kind:, value:)
    kind  = kind.to_s
    value = value.to_s.strip
    raise ArgumentError, "unknown kind: #{kind.inspect}" unless KINDS.include?(kind)

    db.execute('DELETE FROM mute_rules WHERE kind = ? AND value = ?', [kind, value])
    db.changes
  end

  class << self
    private

    def db
      Database.connection
    end
  end
end
