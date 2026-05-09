require_relative 'database'

# Sports Phase S8 — league standings.
#
# Idempotent upsert on (source_provider, league_id, group_name,
# team_id) so the sync script can run hourly without
# accumulating snapshots. New stat columns can be added with a
# follow-up migration without breaking existing reads.
module SportsStandingsStore
  module_function

  def db
    Database.connection
  end

  def find(id)
    db.execute('SELECT * FROM sports_standings WHERE id = ?', [id]).first
  end

  # All standings for a league, grouped by group_name and ordered
  # by position. Used by the /sports/league/:slug page.
  def for_league(league_id)
    db.execute(<<~SQL, [league_id])
      SELECT * FROM sports_standings
      WHERE league_id = ?
      ORDER BY group_name, position
    SQL
  end

  # The team's row in the league standings, used for the inline
  # "NFC East · 1st (11-6)" line on score tiles. Returns nil when
  # standings haven't been synced yet for this team.
  def for_team(team_id)
    db.execute(<<~SQL, [team_id]).first
      SELECT * FROM sports_standings WHERE team_id = ?
      ORDER BY last_synced_at DESC LIMIT 1
    SQL
  end

  def upsert(league_id:, team_id:, group_name:, source_provider:,
             position: nil, wins: nil, losses: nil, ties: nil,
             win_percent: nil, points_for: nil, points_against: nil,
             point_differential: nil, games_behind: nil,
             streak: nil, playoff_seed: nil)
    now_iso = Time.now.utc.iso8601
    args = [league_id, team_id, group_name, position, wins, losses, ties,
            win_percent, points_for, points_against, point_differential,
            games_behind, streak, playoff_seed, source_provider.to_s, now_iso]
    db.execute(<<~SQL, args)
      INSERT INTO sports_standings(
        league_id, team_id, group_name, position, wins, losses, ties,
        win_percent, points_for, points_against, point_differential,
        games_behind, streak, playoff_seed, source_provider, last_synced_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(source_provider, league_id, group_name, team_id) DO UPDATE SET
        position           = excluded.position,
        wins               = excluded.wins,
        losses             = excluded.losses,
        ties               = excluded.ties,
        win_percent        = excluded.win_percent,
        points_for         = excluded.points_for,
        points_against     = excluded.points_against,
        point_differential = excluded.point_differential,
        games_behind       = excluded.games_behind,
        streak             = excluded.streak,
        playoff_seed       = excluded.playoff_seed,
        last_synced_at     = excluded.last_synced_at
    SQL
    db.execute(
      'SELECT * FROM sports_standings WHERE source_provider = ? AND league_id = ? AND group_name = ? AND team_id = ?',
      [source_provider.to_s, league_id, group_name, team_id]
    ).first
  end

  def count
    db.execute('SELECT COUNT(*) AS c FROM sports_standings').first['c']
  end
end
