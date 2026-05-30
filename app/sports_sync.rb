require 'date'
require_relative 'database'
require_relative 'sports_catalog'
require_relative 'sports_leagues_store'
require_relative 'sports_teams_store'
require_relative 'sports_matches_store'
require_relative 'sports_standings_store'
require_relative 'sports_players_store'
require_relative 'sports_follows_store'
require_relative 'providers/espn'
require_relative 'providers/jolpica_f1'
require_relative 'providers/api_sports_hockey'
require_relative 'providers/api_sports_basketball'
require_relative 'providers/api_sports_baseball'
require_relative 'providers/api_sports_football'
require_relative 'providers/api_sports_rugby'
require_relative 'logger'

# One-pass sports refresh: match schedules for followed teams, league
# standings, and ATP/WTA tennis rankings. Used by both the nightly
# Sidekiq cron job (SportsSyncWorker) and the manual entry point
# `scripts/sync_sports.rb` / `make sync-sports`.
#
# Idempotent — every upsert is keyed on (source_provider, external_id),
# so re-running the same window never duplicates rows.
#
# Returns a tally hash so callers can log / surface counts.
module SportsSync
  # Sports for which the per-team schedule endpoint is reliable. Rugby
  # is excluded — it 500s on /teams/<id>/schedule, so we use the
  # league-scoreboard endpoint and filter to the followed team.
  # STUFF #68 — added `baseball` (MLB). The ESPN endpoint
  # /apis/site/v2/sports/baseball/mlb/teams/<id>/schedule returns
  # full team schedules; without it MLB followers got an empty
  # /sports score-tile + an empty Last-game on per-team pages.
  TEAM_SCHEDULE_SPORTS = %w[football basketball soccer baseball].freeze

  def self.run!(logger: AppLogger)
    matches_upserted  = sync_team_schedules!(logger: logger)
    # STUFF #70 follow-up — also pull matches/events for leagues the
    # user follows directly (kind='league' — tournaments + ongoing
    # leagues). Previously the only path was `sync_team_schedules!`,
    # which iterates followed *teams*; following the FIFA World Cup
    # or a Champions League ladder without also following a team in
    # it left the matches table empty.
    matches_upserted += sync_followed_league_events!(logger: logger)
    # STUFF #73 — Formula 1 via Jolpica (the community-maintained
    # Ergast successor). ESPN doesn't expose F1 race data; this
    # closes that gap for users following the F1 league.
    matches_upserted += sync_f1!(logger: logger)
    # STUFF #74 — api-sports.io paid tier. Five sports, one helper.
    # Each call is gated on a per-sport follow check so we don't
    # burn quota for sports nobody follows.
    matches_upserted += sync_api_sports!(logger: logger)
    standings_count  = sync_standings!(logger: logger)
    tennis_count     = sync_tennis_rankings!(logger: logger)

    {
      matches_upserted: matches_upserted,
      matches_total:    SportsMatchesStore.count,
      standings_total:  SportsStandingsStore.count,
      tennis_total:     SportsPlayersStore.count,
      tennis_ranked:    tennis_count
    }
  end

  def self.sync_team_schedules!(logger:)
    followed_team_slugs = SportsFollowsStore.distinct_values('team')
    return 0 if followed_team_slugs.empty?

    upserted = 0
    followed_team_slugs.each do |slug|
      team = SportsTeamsStore.find_by_slug(slug)
      next unless team
      league = SportsLeaguesStore.find(team['league_id'])
      next unless league

      matches = fetch_matches_for(team, league, logger: logger)

      matches.each do |m|
        ensure_team!(m.home_team_external_id, m.home_team_name, m.home_team_logo, league: league)
        ensure_team!(m.away_team_external_id, m.away_team_name, m.away_team_logo, league: league)
        home_team = SportsTeamsStore.find_by_external(league['source_provider'], m.home_team_external_id, league_id: league['id'])
        away_team = SportsTeamsStore.find_by_external(league['source_provider'], m.away_team_external_id, league_id: league['id'])
        SportsMatchesStore.upsert(
          league_id:       league['id'],
          source_provider: league['source_provider'],
          external_id:     m.external_id,
          scheduled_at:    m.scheduled_at,
          status:          m.status,
          home_team_id:    home_team && home_team['id'],
          away_team_id:    away_team && away_team['id'],
          home_score:      m.home_score,
          away_score:      m.away_score,
          period:          m.period,
          venue:           m.venue
        )
        upserted += 1
      end
    end
    upserted
  end

  # STUFF #70 follow-up — fetch matches for every league the user
  # follows directly (kind='league', usually a tournament). Walks
  # ESPN's `league_scoreboard` endpoint to get every event in the
  # league regardless of team — populates FIFA World Cup matches,
  # Champions League fixtures, etc. without requiring a per-team
  # follow. Skips leagues without an ESPN source (most tennis
  # Slams, golf majors, cycling — `source_provider='catalog'`);
  # those will sync once a provider lands for them.
  def self.sync_followed_league_events!(logger:)
    followed_league_slugs = SportsFollowsStore.distinct_values('league')
    return 0 if followed_league_slugs.empty?

    upserted = 0
    followed_league_slugs.each do |slug|
      league = SportsLeaguesStore.find_by_slug(slug)
      next unless league
      next unless league['source_provider'] == 'espn'

      events = Providers::ESPN.league_scoreboard(sport_path: league['external_id'])
      events.each do |m|
        ensure_team!(m.home_team_external_id, m.home_team_name, m.home_team_logo, league: league)
        ensure_team!(m.away_team_external_id, m.away_team_name, m.away_team_logo, league: league)
        home_team = SportsTeamsStore.find_by_external(league['source_provider'], m.home_team_external_id, league_id: league['id'])
        away_team = SportsTeamsStore.find_by_external(league['source_provider'], m.away_team_external_id, league_id: league['id'])
        SportsMatchesStore.upsert(
          league_id:       league['id'],
          source_provider: league['source_provider'],
          external_id:     m.external_id,
          scheduled_at:    m.scheduled_at,
          status:          m.status,
          home_team_id:    home_team && home_team['id'],
          away_team_id:    away_team && away_team['id'],
          home_score:      m.home_score,
          away_score:      m.away_score,
          period:          m.period,
          venue:           m.venue
        )
        upserted += 1
      end
      logger.info('sports_sync_league_events', slug: slug, league: league['name'],
                                                 count: events.length)
    rescue StandardError => e
      logger.warn('sports_sync_league_events_error', slug: slug, message: e.message)
    end
    upserted
  end

  def self.fetch_matches_for(team, league, logger:)
    if TEAM_SCHEDULE_SPORTS.include?(league['sport']) && league['source_provider'] == 'espn'
      Providers::ESPN.team_schedule(
        sport_path:       league['external_id'],
        team_external_id: team['external_id']
      )
    elsif league['sport'] == 'rugby' && league['source_provider'] == 'espn'
      events = Providers::ESPN.league_scoreboard(sport_path: league['external_id'])
      events.select do |m|
        m.home_team_external_id == team['external_id'] ||
          m.away_team_external_id == team['external_id']
      end
    else
      logger.warn('sports_sync', status: :unsupported, slug: team['slug'],
                                  sport: league['sport'], provider: league['source_provider'])
      []
    end
  end

  # Auto-upsert opponent teams so matches can reference both sides. Without
  # this, the opponent renders blank in the UI. Idempotent on
  # (source, external_id); backfills missing image_url / name.
  def self.ensure_team!(external_id, name, logo, league:)
    return if external_id.nil? || external_id.empty?
    existing = SportsTeamsStore.find_by_external(league['source_provider'], external_id, league_id: league['id'])
    if existing
      should_update = (existing['image_url'].to_s.empty? && !logo.to_s.empty?) ||
                      (existing['name'].to_s.empty?      && !name.to_s.empty?)
      return existing unless should_update
      SportsTeamsStore.upsert(
        league_id:       existing['league_id'],
        slug:            existing['slug'],
        name:            existing['name'].to_s.empty? ? name : existing['name'],
        short_name:      existing['short_name'],
        location:        existing['location'],
        source_provider: existing['source_provider'],
        external_id:     existing['external_id'],
        image_url:       existing['image_url'].to_s.empty? ? logo : existing['image_url']
      )
    elsif (catalog_match = SportsTeamsStore.find_by_name_in_league(name, league_id: league['id']))
      # STUFF #68 — pre-existing catalog row (manually-seeded slug
      # like 'phillies', source_provider='catalog') matches the ESPN
      # payload's team by name. Promote that row to ESPN-tracked
      # by writing the real external_id + source_provider, so
      # matches + standings + follows all converge on a single row.
      # Without this, a second `<league>-team-<external_id>` row got
      # created on the first sync — and the user's 'phillies' follow
      # then pointed at an empty row with no matches.
      SportsTeamsStore.upsert(
        league_id:       catalog_match['league_id'],
        slug:            catalog_match['slug'],
        name:            catalog_match['name'],
        short_name:      catalog_match['short_name'],
        location:        catalog_match['location'],
        source_provider: league['source_provider'],
        external_id:     external_id,
        image_url:       catalog_match['image_url'].to_s.empty? ? logo : catalog_match['image_url']
      )
    else
      opponent_slug = "#{league['slug']}-team-#{external_id}"
      SportsTeamsStore.upsert(
        league_id:       league['id'],
        slug:            opponent_slug,
        name:            name.to_s.empty? ? opponent_slug : name,
        short_name:      nil,
        source_provider: league['source_provider'],
        external_id:     external_id,
        image_url:       logo
      )
    end
  end

  # Wider than the match sync (which is follow-gated): standings are
  # globally interesting and one HTTP per league is cheap.
  def self.sync_standings!(logger:)
    count = 0
    SportsLeaguesStore.all.each do |league|
      next unless league['source_provider'] == 'espn'

      groups = Providers::ESPN.standings(sport_path: league['external_id'])
      groups.each do |group|
        group.entries.each_with_index do |entry, idx|
          # STUFF #68 — go through ensure_team! so the standings sync
          # gets the same catalog-promotion behaviour as the schedule
          # sync. Previously the inline branch always auto-created a
          # `<league>-team-<external_id>` row, which is why MLB
          # standings + catalog rows ended up split into duplicates.
          team_row = ensure_team!(
            entry.team_external_id, entry.team_name, entry.team_logo, league: league
          )
          next unless team_row

          SportsStandingsStore.upsert(
            league_id:           league['id'],
            team_id:             team_row['id'],
            group_name:          group.group_name,
            source_provider:     league['source_provider'],
            position:            entry.position || (idx + 1),
            wins:                entry.wins,
            losses:              entry.losses,
            ties:                entry.ties,
            win_percent:         entry.win_percent,
            points_for:          entry.points_for,
            points_against:      entry.points_against,
            point_differential:  entry.point_differential,
            games_behind:        entry.games_behind,
            streak:              entry.streak,
            playoff_seed:        entry.playoff_seed
          )
          count += 1
        end
      end
    end
    count
  rescue StandardError => e
    logger.warn('sports_sync_standings_error', error: e.message)
    count
  end

  # STUFF #73 — Formula 1 via Jolpica. Looked up only when at least
  # one user follows the F1 league (or its parent catalog), so we
  # don't hit the API for a dataset nobody cares about. Inserts every
  # race in the current season as a sports_matches row with
  # `home_team_id` + `away_team_id` both NULL (F1 isn't team-vs-team);
  # `venue` carries the circuit name + country; `period` carries the
  # round label so the /sports/league/f1 view can present "Round 7
  # — Monaco Grand Prix" cleanly.
  CURRENT_F1_SEASON = Date.today.year

  def self.sync_f1!(logger:)
    return 0 unless f1_followed?
    league = ensure_f1_league_row!
    return 0 unless league

    races = Providers::JolpicaF1.season(CURRENT_F1_SEASON)
    upserted = 0
    races.each do |r|
      SportsMatchesStore.upsert(
        league_id:       league['id'],
        source_provider: 'jolpica',
        external_id:     "f1-#{r.season}-#{r.round}",
        scheduled_at:    r.scheduled_at,
        status:          r.status,
        home_team_id:    nil,
        away_team_id:    nil,
        period:          "Round #{r.round} — #{r.race_name}",
        venue:           [r.circuit_name, r.country].compact.join(', ')
      )
      upserted += 1
    end
    logger.info('sports_sync_f1', season: CURRENT_F1_SEASON, count: upserted)
    upserted
  rescue StandardError => e
    logger.warn('sports_sync_f1_error', message: e.message)
    0
  end

  # Skip the F1 fetch entirely if no user follows the F1 league. Cheap
  # query — one DISTINCT scan of sports_follows.
  def self.f1_followed?
    SportsFollowsStore.distinct_values('league').include?('formula-1')
  end

  def self.ensure_f1_league_row!
    existing = SportsLeaguesStore.find_by_slug('formula-1')
    return existing if existing
    SportsLeaguesStore.upsert(
      slug: 'formula-1', name: 'Formula 1', sport: 'motorsport',
      source_provider: 'jolpica', external_id: 'f1'
    )
  end

  # STUFF #74 — api-sports.io paid-tier sync.
  # Walks every league the user follows whose source_provider is
  # 'api-sports', resolves the numeric league_id from the catalog,
  # routes to the right sport provider, and upserts matches. Season
  # is resolved by trying current_year-1 then current_year-2 so the
  # sync stays live even when the API lags a season behind.
  API_SPORTS_PROVIDERS = {
    'hockey'     => Providers::ApiSportsHockey,
    'rugby'      => Providers::ApiSportsRugby,
    'baseball'   => Providers::ApiSportsBaseball,
    'basketball' => Providers::ApiSportsBasketball,
    'football'   => Providers::ApiSportsFootball
  }.freeze

  def self.sync_api_sports!(logger:)
    return 0 if ENV['API_SPORTS_KEY'].to_s.empty?

    followed_slugs = SportsFollowsStore.distinct_values('league')
    return 0 if followed_slugs.empty?

    total = 0
    followed_slugs.each do |slug|
      league = SportsLeaguesStore.find_by_slug(slug)
      next unless league
      next unless league['source_provider'] == 'api-sports'

      catalog_entry = SportsCatalog.all_leagues.find { |lg| lg[:slug] == slug }
      api_league_id = catalog_entry&.dig(:api_sports_league_id)
      next unless api_league_id

      provider = API_SPORTS_PROVIDERS[league['sport']]
      next unless provider

      # Try current season then one year back — api-sports often lags
      # one season. Whichever has data wins.
      games = []
      api_sports_seasons_to_try.each do |season|
        games = provider.fixtures(league_id: api_league_id, season: season)
        break unless games.empty?
      end

      games.each do |g|
        ensure_team!(g[:home_team_external_id], g[:home_team_name],
                     g[:home_team_logo], league: league)
        ensure_team!(g[:away_team_external_id], g[:away_team_name],
                     g[:away_team_logo], league: league)
        home = SportsTeamsStore.find_by_external(
          'api-sports', g[:home_team_external_id], league_id: league['id']
        )
        away = SportsTeamsStore.find_by_external(
          'api-sports', g[:away_team_external_id], league_id: league['id']
        )
        SportsMatchesStore.upsert(
          league_id:       league['id'],
          source_provider: 'api-sports',
          external_id:     "#{league['sport']}-#{g[:external_id]}",
          scheduled_at:    g[:scheduled_at],
          status:          g[:status],
          home_team_id:    home&.dig('id'),
          away_team_id:    away&.dig('id'),
          home_score:      g[:home_score],
          away_score:      g[:away_score],
          period:          nil,
          venue:           g[:venue]
        )
        total += 1
      end
      logger.info('sports_sync_api_sports', slug: slug, sport: league['sport'],
                                             count: games.length)
    rescue StandardError => e
      logger.warn('sports_sync_api_sports_league_error', slug: slug, message: e.message)
    end
    total
  rescue StandardError => e
    logger.warn('sports_sync_api_sports_error', message: e.message)
    0
  end

  def self.api_sports_seasons_to_try
    year = Date.today.year
    [year - 1, year - 2]
  end

  # Cron-only refresh path; forces ESPN re-fetch regardless of TTL so
  # the nightly run always reflects the latest state. The /sports/tennis
  # route uses refresh_if_stale! instead so the on-page-load path is
  # cheaper.
  def self.sync_tennis_rankings!(logger:)
    total = 0
    %w[atp wta].each do |tour|
      total += SportsPlayersStore.refresh!(tour: tour)
    end
    total
  rescue StandardError => e
    logger.warn('sports_sync_tennis_error', error: e.message)
    total
  end
end
