require_relative 'api_sports_base'

# STUFF #74 — soccer leagues beyond ESPN's reach: Bundesliga 2, lower
# English divisions, Saudi Pro League, Eredivisie. ESPN covers Premier
# League / La Liga / Serie A / etc. via existing FeedCatalog leagues
# so we only call api-sports for the long tail.
#
# Reference: https://api-sports.io/documentation/football/v3
module Providers
  module ApiSportsFootball
    include ApiSportsBase
    HOST = 'v3.football.api-sports.io'.freeze

    # Selected league IDs (not exhaustive). Add more by hitting
    # /leagues?search=<name> and grabbing the id from the JSON.
    BUNDESLIGA_2_LEAGUE_ID  = 79
    EREDIVISIE_LEAGUE_ID    = 88
    SAUDI_PRO_LEAGUE_ID     = 307
    LIGUE_2_LEAGUE_ID       = 62

    module_function

    def fixtures(league_id:, season: Date.today.year, http_get: nil)
      raw = ApiSportsFootball.get('/fixtures',
                                  query: { league: league_id, season: season },
                                  http_get: http_get)
      raw.map { |g| normalize_fixture(g) }.compact
    end

    def normalize_fixture(f)
      fx = f['fixture'] || {}
      {
        external_id:           fx['id'].to_s,
        scheduled_at:          fx['date'],
        status:                map_status(fx.dig('status', 'short')),
        home_team_external_id: f.dig('teams', 'home', 'id').to_s,
        home_team_name:        f.dig('teams', 'home', 'name'),
        home_team_logo:        f.dig('teams', 'home', 'logo'),
        away_team_external_id: f.dig('teams', 'away', 'id').to_s,
        away_team_name:        f.dig('teams', 'away', 'name'),
        away_team_logo:        f.dig('teams', 'away', 'logo'),
        home_score:            f.dig('goals', 'home'),
        away_score:            f.dig('goals', 'away'),
        venue:                 fx.dig('venue', 'name')
      }
    rescue StandardError => e
      AppLogger.warn('api_sports_football_normalize', message: e.message)
      nil
    end

    FINAL_CODES     = %w[FT AET PEN].freeze
    LIVE_CODES      = %w[1H HT 2H ET P LIVE].freeze
    POSTPONED_CODES = %w[PST CANC ABD].freeze

    def map_status(code)
      return 'scheduled'  if code.nil?
      return 'final'      if FINAL_CODES.include?(code)
      return 'live'       if LIVE_CODES.include?(code)
      return 'postponed'  if POSTPONED_CODES.include?(code)
      'scheduled'
    end
  end
end
