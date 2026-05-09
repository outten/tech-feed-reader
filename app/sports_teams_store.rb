require_relative 'database'

# Wrapper around sports_teams. Every team belongs to exactly one
# league (`league_id`). Idempotent upsert by (source_provider,
# external_id) so re-running the seed never duplicates.
#
# Distinct from the existing app/sports_teams.rb Ruby module —
# that module hard-codes the user's *preferred* teams (Eagles,
# Sixers, Union, etc) plus their RSS feed URLs. This store backs
# the structured-data side: every team we have provider-side data
# for, FK'd to leagues + matches.
module SportsTeamsStore
  module_function

  def db
    Database.connection
  end

  def all
    db.execute('SELECT * FROM sports_teams ORDER BY id')
  end

  def find(id)
    db.execute('SELECT * FROM sports_teams WHERE id = ?', [id]).first
  end

  def find_by_slug(slug)
    db.execute('SELECT * FROM sports_teams WHERE slug = ?', [slug.to_s]).first
  end

  # ESPN reuses numeric team IDs across sports (id=8 is Detroit
  # Lions in NFL AND New Zealand in rugby), so callers MUST scope
  # by league_id. The legacy 2-arg form is supported for tests
  # that pre-date the league_id requirement.
  def find_by_external(source_provider, external_id, league_id: nil)
    if league_id
      db.execute(
        'SELECT * FROM sports_teams WHERE source_provider = ? AND external_id = ? AND league_id = ?',
        [source_provider.to_s, external_id.to_s, league_id]
      ).first
    else
      db.execute(
        'SELECT * FROM sports_teams WHERE source_provider = ? AND external_id = ?',
        [source_provider.to_s, external_id.to_s]
      ).first
    end
  end

  def for_league(league_id)
    db.execute('SELECT * FROM sports_teams WHERE league_id = ? ORDER BY name', [league_id])
  end

  def upsert(league_id:, slug:, name:, source_provider:, external_id:,
             short_name: nil, location: nil, image_url: nil)
    existing = find_by_external(source_provider, external_id, league_id: league_id) ||
               find_by_slug(slug)
    if existing
      args = [league_id, name, short_name, location, image_url,
              source_provider.to_s, external_id.to_s, existing['id']]
      db.execute(<<~SQL, args)
        UPDATE sports_teams
        SET league_id = ?, name = ?, short_name = ?, location = ?, image_url = ?,
            source_provider = ?, external_id = ?
        WHERE id = ?
      SQL
      find(existing['id'])
    else
      args = [league_id, slug, name, short_name, location, image_url,
              source_provider.to_s, external_id.to_s]
      db.execute(<<~SQL, args)
        INSERT INTO sports_teams(league_id, slug, name, short_name, location, image_url,
                                 source_provider, external_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      find(db.last_insert_row_id)
    end
  end

  def count
    db.execute('SELECT COUNT(*) AS c FROM sports_teams').first['c']
  end
end
