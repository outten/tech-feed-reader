require_relative 'database'

# Per-user wrapper around sports_follows. The "I follow these" list
# drives the sync script (which entities get pulled per cron run) and
# the per-team / per-player UI.
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

  def all(user_id)
    db.execute(
      'SELECT * FROM sports_follows WHERE user_id = ? ORDER BY kind, created_at',
      [user_id.to_i]
    )
  end

  def for_kind(user_id, kind)
    raise ArgumentError, "unknown kind: #{kind.inspect}" unless KINDS.include?(kind.to_s)
    db.execute(
      'SELECT * FROM sports_follows WHERE user_id = ? AND kind = ? ORDER BY created_at',
      [user_id.to_i, kind.to_s]
    )
  end

  def follow?(user_id, kind, value)
    !db.execute(
      'SELECT 1 FROM sports_follows WHERE user_id = ? AND kind = ? AND value = ? LIMIT 1',
      [user_id.to_i, kind.to_s, value.to_s]
    ).first.nil?
  end

  # Idempotent — re-following is a no-op (UNIQUE(user_id, kind, value)).
  # Returns true on insert, false on already-present.
  def add(user_id:, kind:, value:)
    raise ArgumentError, "unknown kind: #{kind.inspect}"  unless KINDS.include?(kind.to_s)
    raise ArgumentError, 'value must be non-empty'        if value.to_s.strip.empty?

    db.execute(
      'INSERT INTO sports_follows(user_id, kind, value) VALUES (?, ?, ?) ON CONFLICT DO NOTHING',
      [user_id.to_i, kind.to_s, value.to_s]
    )
    db.changes.positive?
  end

  def remove(user_id:, kind:, value:)
    db.execute(
      'DELETE FROM sports_follows WHERE user_id = ? AND kind = ? AND value = ?',
      [user_id.to_i, kind.to_s, value.to_s]
    )
    db.changes
  end

  def count(user_id)
    db.execute('SELECT COUNT(*) AS c FROM sports_follows WHERE user_id = ?', [user_id.to_i]).first['c']
  end

  # Sync-script helper: every user × every followed entity, so the
  # nightly cron can pull what every user follows in one pass.
  def distinct_values(kind)
    raise ArgumentError, "unknown kind: #{kind.inspect}" unless KINDS.include?(kind.to_s)
    db.execute(
      'SELECT DISTINCT value FROM sports_follows WHERE kind = ? ORDER BY value',
      [kind.to_s]
    ).map { |r| r['value'] }
  end
end
