require_relative 'database'

# Wrapper around sports_follows. The user's "I follow these" list,
# drives the sync script (which entities get pulled per cron run)
# and will drive the per-team / per-player UI (S6 second half +
# S7 tennis follows).
#
# kind  ∈ team | player | league
# value = the slug of the followed entity (sports_teams.slug,
#                                          sports_players.slug,
#                                          sports_leagues.slug)
module SportsFollowsStore
  KINDS = %w[team player league].freeze

  module_function

  def db
    Database.connection
  end

  def all
    db.execute('SELECT * FROM sports_follows ORDER BY kind, created_at')
  end

  def for_kind(kind)
    raise ArgumentError, "unknown kind: #{kind.inspect}" unless KINDS.include?(kind.to_s)
    db.execute('SELECT * FROM sports_follows WHERE kind = ? ORDER BY created_at', [kind.to_s])
  end

  def follow?(kind, value)
    !db.execute(
      'SELECT 1 FROM sports_follows WHERE kind = ? AND value = ? LIMIT 1',
      [kind.to_s, value.to_s]
    ).first.nil?
  end

  # Idempotent — re-following is a no-op (relies on the
  # UNIQUE(kind, value) constraint). Returns true if a new row was
  # inserted, false if it already existed.
  def add(kind:, value:)
    raise ArgumentError, "unknown kind: #{kind.inspect}"  unless KINDS.include?(kind.to_s)
    raise ArgumentError, 'value must be non-empty'        if value.to_s.strip.empty?

    db.execute(
      'INSERT OR IGNORE INTO sports_follows(kind, value) VALUES (?, ?)',
      [kind.to_s, value.to_s]
    )
    db.changes.positive?
  end

  def remove(kind:, value:)
    db.execute('DELETE FROM sports_follows WHERE kind = ? AND value = ?', [kind.to_s, value.to_s])
    db.changes
  end

  def count
    db.execute('SELECT COUNT(*) AS c FROM sports_follows').first['c']
  end
end
