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
             country: nil, image_url: nil)
    existing = find_by_external(source_provider, external_id) ||
               find_by_slug(slug)
    if existing
      args = [sport, full_name, country, image_url,
              source_provider.to_s, external_id.to_s, existing['id']]
      db.execute(<<~SQL, args)
        UPDATE sports_players
        SET sport = ?, full_name = ?, country = ?, image_url = ?,
            source_provider = ?, external_id = ?
        WHERE id = ?
      SQL
      find(existing['id'])
    else
      args = [sport, slug, full_name, country, image_url,
              source_provider.to_s, external_id.to_s]
      db.execute(<<~SQL, args)
        INSERT INTO sports_players(sport, slug, full_name, country, image_url,
                                    source_provider, external_id)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      SQL
      find(db.last_insert_row_id)
    end
  end

  def count
    db.execute('SELECT COUNT(*) AS c FROM sports_players').first['c']
  end
end
