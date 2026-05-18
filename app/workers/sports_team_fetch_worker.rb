require 'sidekiq'
require_relative '../sports_teams_store'
require_relative '../sports_leagues_store'
require_relative '../sports_matches_store'
require_relative '../providers/espn'
require_relative '../logger'

# STUFF #43 — eager sync of a single team's schedule + recent results
# right after a user follows it. Without this, a newly-followed team
# would sit empty on /sports until the next nightly sync (which also
# isn't scheduled yet). Enqueued from POST /sports/teams/follow so the
# user sees data within ~30s of clicking the button.
#
# Idempotent: SportsMatchesStore.upsert dedups by
# (source_provider, external_id), so re-running the job doesn't
# duplicate. Bails quietly if the team or league row is gone (deleted
# between enqueue and run, e.g. via teardown in tests).
class SportsTeamFetchWorker
  include Sidekiq::Worker

  sidekiq_options queue: :default

  def perform(team_id)
    team = SportsTeamsStore.find(team_id.to_i)
    unless team
      AppLogger.warn('sports_team_fetch_skip', team_id: team_id, reason: 'not_found')
      return
    end

    league = SportsLeaguesStore.find(team['league_id'].to_i)
    unless league
      AppLogger.warn('sports_team_fetch_skip', team_id: team_id, reason: 'no_league')
      return
    end

    sport_path = league['external_id']
    matches = Providers::ESPN.team_schedule(sport_path: sport_path,
                                            team_external_id: team['external_id'])
    return if matches.empty?

    # Mirror the team-resolution + match-upsert sequence from
    # scripts/sync_sports.rb. Kept inline (rather than extracted to
    # a helper) to keep this PR focused; the duplication is small +
    # well-contained. If a third caller appears, refactor.
    matches.each do |m|
      ensure_team(league, m.home_team_external_id, m.home_team_name, m.home_team_logo)
      ensure_team(league, m.away_team_external_id, m.away_team_name, m.away_team_logo)
      home = SportsTeamsStore.find_by_external(league['source_provider'], m.home_team_external_id, league_id: league['id'])
      away = SportsTeamsStore.find_by_external(league['source_provider'], m.away_team_external_id, league_id: league['id'])
      SportsMatchesStore.upsert(
        league_id:       league['id'],
        source_provider: league['source_provider'],
        external_id:     m.external_id,
        scheduled_at:    m.scheduled_at,
        status:          m.status,
        home_team_id:    home && home['id'],
        away_team_id:    away && away['id'],
        home_score:      m.home_score,
        away_score:      m.away_score,
        period:          m.period,
        venue:           m.venue
      )
    rescue StandardError => e
      AppLogger.warn('sports_team_fetch_match_skip', team_id: team_id,
                     external_id: m.respond_to?(:external_id) ? m.external_id : nil,
                     message: e.message)
    end
    AppLogger.info('sports_team_fetch_done', team_id: team_id, league: league['slug'],
                   count: matches.length)
  end

  private

  def ensure_team(league, side_external_id, side_name, side_logo)
    return if side_external_id.nil? || side_external_id.to_s.empty?
    existing = SportsTeamsStore.find_by_external(league['source_provider'], side_external_id, league_id: league['id'])
    if existing.nil?
      SportsTeamsStore.upsert(
        league_id:       league['id'],
        slug:            "#{league['slug']}-team-#{side_external_id}",
        name:            side_name.to_s.empty? ? "team-#{side_external_id}" : side_name,
        source_provider: league['source_provider'],
        external_id:     side_external_id,
        image_url:       side_logo
      )
    end
  end
end
