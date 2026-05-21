require_relative 'database'
require_relative 'sports_leagues_store'
require_relative 'sports_teams_store'
require_relative 'sports_matches_store'
require_relative 'sports_standings_store'
require_relative 'sports_players_store'
require_relative 'sports_follows_store'
require_relative 'providers/espn'
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
  TEAM_SCHEDULE_SPORTS = %w[football basketball soccer].freeze

  def self.run!(logger: AppLogger)
    matches_upserted = sync_team_schedules!(logger: logger)
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
          team_row = SportsTeamsStore.find_by_external(
            league['source_provider'], entry.team_external_id, league_id: league['id']
          )
          team_row ||= SportsTeamsStore.upsert(
            league_id:       league['id'],
            slug:            "#{league['slug']}-team-#{entry.team_external_id}",
            name:            entry.team_name.to_s.empty? ? entry.team_external_id : entry.team_name,
            source_provider: league['source_provider'],
            external_id:     entry.team_external_id,
            image_url:       entry.team_logo
          )

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
