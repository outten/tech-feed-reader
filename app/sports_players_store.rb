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

  # STUFF #46 — opportunistic on-page-load refresh for /sports/tennis.
  # When the last sync for this tour is older than TENNIS_SYNC_TTL_SECONDS
  # (or there's no data at all), call ESPN and upsert. Returns :refreshed
  # or :fresh so callers can log + smoke-test.
  #
  # Adds ~500ms-1s to the first request after the TTL expires; cached
  # for everyone after that. Two concurrent first-request users could
  # both fire the ESPN call — harmless duplication, upsert is idempotent.
  TENNIS_SYNC_TTL_SECONDS = 60 * 60 * 12 # 12h — ATP/WTA rankings update weekly

  def refresh_if_stale!(tour:)
    tour = tour.to_s
    last = newest_sync_at(tour: tour)
    if last && (Time.now.utc - Time.parse(last)) < TENNIS_SYNC_TTL_SECONDS
      return :fresh
    end
    refresh!(tour: tour)
    :refreshed
  end

  def newest_sync_at(tour:)
    db.execute(
      'SELECT MAX(last_synced_at) AS m FROM sports_players WHERE tour = ?',
      [tour.to_s]
    ).first['m']
  end

  # Pull ESPN rankings for a single tour and upsert every entry.
  # Returns the count upserted. Extracted from scripts/sync_sports.rb
  # so the /sports/tennis route can call it directly on page load.
  def refresh!(tour:)
    require_relative 'providers/espn'
    entries = Providers::ESPN.tennis_rankings(tour: tour.to_s)
    return 0 if entries.empty?

    entries.each do |e|
      slug = tennis_player_slug(e.full_name)
      next unless slug && e.athlete_external_id && !e.athlete_external_id.to_s.empty?

      upsert(
        sport:           'tennis',
        slug:            slug,
        full_name:       e.full_name,
        country:         e.country,
        image_url:       e.headshot_url,
        tour:            e.tour,
        current_rank:    e.current_rank,
        previous_rank:   e.previous_rank,
        points:          e.points,
        trend:           e.trend,
        headshot_url:    e.headshot_url,
        flag_url:        e.flag_url,
        source_provider: 'espn',
        external_id:     e.athlete_external_id
      )
    end
    entries.length
  end

  # slugify a tennis player display name. "Iga Świątek" → "iga-swiatek".
  # Strips diacritics via Unicode decomposition (NFD then ASCII filter).
  def tennis_player_slug(full_name)
    s = full_name.to_s.unicode_normalize(:nfd).gsub(/[^\x00-\x7F]/, '')
    s = s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/(^-|-$)/, '')
    s.empty? ? nil : s
  end

  def count
    db.execute('SELECT COUNT(*) AS c FROM sports_players').first['c']
  end
end
