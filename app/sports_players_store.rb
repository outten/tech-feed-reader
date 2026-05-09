require_relative 'database'

# Wrapper around sports_players. Schema exists from S3 onwards but
# the player-following UI (Phase S7 — tennis ATP/WTA player follows)
# is a follow-up. Right now this is just enough to track players if
# a future provider populates them.
module SportsPlayersStore
  module_function

  def db
    Database.connection
  end

  def find(id)
    db.execute('SELECT * FROM sports_players WHERE id = ?', [id]).first
  end

  def find_by_slug(slug)
    db.execute('SELECT * FROM sports_players WHERE slug = ?', [slug.to_s]).first
  end

  def find_by_external(source_provider, external_id)
    db.execute(
      'SELECT * FROM sports_players WHERE source_provider = ? AND external_id = ?',
      [source_provider.to_s, external_id.to_s]
    ).first
  end

  def upsert(sport:, slug:, full_name:, source_provider:, external_id:,
             country: nil, image_url: nil,
             tour: nil, current_rank: nil, previous_rank: nil, points: nil,
             trend: nil, headshot_url: nil, flag_url: nil)
    existing = find_by_external(source_provider, external_id) ||
               find_by_slug(slug)
    now_iso  = Time.now.utc.iso8601

    if existing
      args = [sport, full_name, country, image_url,
              tour, current_rank, previous_rank, points,
              trend, headshot_url, flag_url, now_iso,
              source_provider.to_s, external_id.to_s, existing['id']]
      db.execute(<<~SQL, args)
        UPDATE sports_players
        SET sport = ?, full_name = ?, country = ?, image_url = ?,
            tour = ?, current_rank = ?, previous_rank = ?, points = ?,
            trend = ?, headshot_url = ?, flag_url = ?, last_synced_at = ?,
            source_provider = ?, external_id = ?
        WHERE id = ?
      SQL
      find(existing['id'])
    else
      args = [sport, slug, full_name, country, image_url,
              tour, current_rank, previous_rank, points,
              trend, headshot_url, flag_url, now_iso,
              source_provider.to_s, external_id.to_s]
      db.execute(<<~SQL, args)
        INSERT INTO sports_players(sport, slug, full_name, country, image_url,
                                    tour, current_rank, previous_rank, points,
                                    trend, headshot_url, flag_url, last_synced_at,
                                    source_provider, external_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      find(db.last_insert_row_id)
    end
  end

  # Tennis rankings page query. ATP / WTA top-N players, ordered
  # by current rank. Returns the full row so the view has access
  # to country, headshot, points, trend, etc.
  def top_ranked(tour:, limit: 50)
    db.execute(<<~SQL, [tour.to_s, limit])
      SELECT * FROM sports_players
      WHERE tour = ? AND current_rank IS NOT NULL
      ORDER BY current_rank ASC
      LIMIT ?
    SQL
  end

  def count
    db.execute('SELECT COUNT(*) AS c FROM sports_players').first['c']
  end
end
