require_relative 'database'

# Wrapper around sports_leagues. One row per league we sync from
# (NFL / NBA / MLS / International Rugby for v1; ATP/WTA + Super
# Rugby Pacific can land later when more providers come online).
#
# Idempotent upsert by (source_provider, external_id) so the seed
# script is safe to re-run as new leagues get added.
module SportsLeaguesStore
  module_function

  def db
    Database.connection
  end

  def all
    db.execute('SELECT * FROM sports_leagues ORDER BY id')
  end

  def find(id)
    db.execute('SELECT * FROM sports_leagues WHERE id = ?', [id]).first
  end

  def find_by_slug(slug)
    db.execute('SELECT * FROM sports_leagues WHERE slug = ?', [slug.to_s]).first
  end

  def find_by_external(source_provider, external_id)
    db.execute(
      'SELECT * FROM sports_leagues WHERE source_provider = ? AND external_id = ?',
      [source_provider.to_s, external_id.to_s]
    ).first
  end

  # Idempotent — re-running with the same (source, external_id)
  # updates the human-facing fields but keeps the row id stable.
  def upsert(slug:, name:, sport:, source_provider:, external_id:,
             country: nil, season_year: nil)
    existing = find_by_external(source_provider, external_id) ||
               find_by_slug(slug)
    if existing
      db.execute(<<~SQL, [name, sport, country, season_year, source_provider.to_s, external_id.to_s, existing['id']])
        UPDATE sports_leagues
        SET name = ?, sport = ?, country = ?, season_year = ?,
            source_provider = ?, external_id = ?
        WHERE id = ?
      SQL
      find(existing['id'])
    else
      db.execute(<<~SQL, [slug, name, sport, source_provider.to_s, external_id.to_s, country, season_year])
        INSERT INTO sports_leagues(slug, name, sport, source_provider, external_id, country, season_year)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      SQL
      find(db.last_insert_row_id)
    end
  end

  def count
    db.execute('SELECT COUNT(*) AS c FROM sports_leagues').first['c']
  end
end
