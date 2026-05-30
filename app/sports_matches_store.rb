require_relative 'database'

# Wrapper around sports_matches. Idempotent upsert by
# (source_provider, external_id) — the sync script can run hourly
# without duplicating rows. Final scores don't change post-game,
# but `last_synced_at` lets a future optimisation skip already-
# final rows.
module SportsMatchesStore
  STATUSES = %w[scheduled live final postponed cancelled].freeze

  module_function

  def db
    Database.connection
  end

  def find(id)
    db.execute('SELECT * FROM sports_matches WHERE id = ?', [id]).first
  end

  def find_by_external(source_provider, external_id)
    db.execute(
      'SELECT * FROM sports_matches WHERE source_provider = ? AND external_id = ?',
      [source_provider.to_s, external_id.to_s]
    ).first
  end

  # Recent finals for a team, newest first. Used by the upcoming
  # team-detail UI (Phase S6 second half).
  def recent_finals_for_team(team_id, limit: 5)
    db.execute(<<~SQL, [team_id, team_id, limit])
      SELECT * FROM sports_matches
      WHERE status = 'final'
        AND (home_team_id = ? OR away_team_id = ?)
      ORDER BY scheduled_at DESC
      LIMIT ?
    SQL
  end

  # Upcoming scheduled matches for a team, soonest first.
  def upcoming_for_team(team_id, limit: 5, now: Time.now.utc)
    db.execute(<<~SQL, [team_id, team_id, now.iso8601, limit])
      SELECT * FROM sports_matches
      WHERE status IN ('scheduled', 'live')
        AND (home_team_id = ? OR away_team_id = ?)
        AND scheduled_at >= ?
      ORDER BY scheduled_at ASC
      LIMIT ?
    SQL
  end

  # STUFF #70 follow-up — per-league fixtures + results. Drives the
  # Upcoming / Recent sections on /sports/league/:slug for tournaments
  # the user has followed (FIFA World Cup, Champions League, etc.).
  # Mirrors the per-team helpers above but filters by league_id.
  def upcoming_for_league(league_id, limit: 12, now: Time.now.utc)
    db.execute(<<~SQL, [league_id, now.iso8601, limit])
      SELECT * FROM sports_matches
      WHERE status IN ('scheduled', 'live')
        AND league_id = ?
        AND scheduled_at >= ?
      ORDER BY scheduled_at ASC
      LIMIT ?
    SQL
  end

  def recent_finals_for_league(league_id, limit: 12)
    db.execute(<<~SQL, [league_id, limit])
      SELECT * FROM sports_matches
      WHERE status = 'final' AND league_id = ?
      ORDER BY scheduled_at DESC
      LIMIT ?
    SQL
  end

  # Live matches across the whole table (used by /sports overview
  # "Live now" section once the UI ships).
  def live
    db.execute("SELECT * FROM sports_matches WHERE status = 'live' ORDER BY scheduled_at")
  end

  # Phase S9 — upcoming matches across every team the user follows
  # (sports_follows kind=team), within the next `days_forward` days.
  # Drives /sports/calendar and the iCal export.
  def upcoming_for_followed_teams(user_id, days_forward: 30, now: Time.now.utc)
    cutoff = (now + days_forward * 86_400).iso8601
    uid    = user_id.to_i
    db.execute(<<~SQL, [now.iso8601, cutoff, uid, uid])
      SELECT m.* FROM sports_matches m
      WHERE m.status IN ('scheduled', 'live')
        AND m.scheduled_at >= ?
        AND m.scheduled_at <= ?
        AND (
          m.home_team_id IN (SELECT t.id FROM sports_teams t
                              JOIN sports_follows f ON f.kind = 'team' AND f.value = t.slug AND f.user_id = ?)
          OR m.away_team_id IN (SELECT t.id FROM sports_teams t
                                 JOIN sports_follows f ON f.kind = 'team' AND f.value = t.slug AND f.user_id = ?)
        )
      ORDER BY m.scheduled_at ASC
    SQL
  end

  # Idempotent upsert. Returns the row.
  def upsert(league_id:, source_provider:, external_id:, scheduled_at:, status:,
             home_team_id: nil, away_team_id: nil,
             home_score: nil, away_score: nil, period: nil, venue: nil)
    raise ArgumentError, "unknown status: #{status.inspect}" unless STATUSES.include?(status.to_s)
    now_iso = Time.now.utc.iso8601

    existing = find_by_external(source_provider, external_id)
    if existing
      args = [league_id, home_team_id, away_team_id, scheduled_at, status.to_s,
              home_score, away_score, period, venue, now_iso, existing['id']]
      db.execute(<<~SQL, args)
        UPDATE sports_matches
        SET league_id = ?, home_team_id = ?, away_team_id = ?,
            scheduled_at = ?, status = ?,
            home_score = ?, away_score = ?, period = ?, venue = ?,
            last_synced_at = ?
        WHERE id = ?
      SQL
      find(existing['id'])
    else
      args = [league_id, home_team_id, away_team_id, scheduled_at, status.to_s,
              home_score, away_score, period, venue,
              source_provider.to_s, external_id.to_s, now_iso]
      db.execute(<<~SQL, args)
        INSERT INTO sports_matches(league_id, home_team_id, away_team_id,
                                    scheduled_at, status,
                                    home_score, away_score, period, venue,
                                    source_provider, external_id, last_synced_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      find(db.last_insert_row_id)
    end
  end

  def count
    db.execute('SELECT COUNT(*) AS c FROM sports_matches').first['c']
  end
end
