require_relative 'api_sports_base'

# STUFF #74 — proper rugby fixtures. ESPN's coverage is limited (only
# the Rugby Championship works via league_scoreboard, and even then
# only for groups/standings). API-Sports covers Six Nations, Super
# Rugby, URC, Premiership Rugby, etc.
#
# Reference: https://api-sports.io/documentation/rugby/v1
module Providers
  module ApiSportsRugby
    include ApiSportsBase
    HOST = 'v1.rugby.api-sports.io'.freeze

    SIX_NATIONS_LEAGUE_ID    = 51  # verified live 2024-05-30
    SUPER_RUGBY_LEAGUE_ID    = 71
    PREMIERSHIP_LEAGUE_ID    = 13  # Gallagher Premiership, England
    URC_LEAGUE_ID            = 76  # United Rugby Championship
    RUGBY_CHAMPIONSHIP_ID    = 85  # The Rugby Championship (southern hemisphere)

    module_function

    def fixtures(league_id:, season: Date.today.year, http_get: nil)
      raw = ApiSportsRugby.get('/games',
                               query: { league: league_id, season: season },
                               http_get: http_get)
      raw.map { |g| normalize_game(g) }.compact
    end

    def normalize_game(g)
      {
        external_id:           g['id'].to_s,
        scheduled_at:          g['date'],
        status:                map_status(g.dig('status', 'short')),
        home_team_external_id: g.dig('teams', 'home', 'id').to_s,
        home_team_name:        g.dig('teams', 'home', 'name'),
        home_team_logo:        g.dig('teams', 'home', 'logo'),
        away_team_external_id: g.dig('teams', 'away', 'id').to_s,
        away_team_name:        g.dig('teams', 'away', 'name'),
        away_team_logo:        g.dig('teams', 'away', 'logo'),
        home_score:            g.dig('scores', 'home'),
        away_score:            g.dig('scores', 'away'),
        venue:                 nil
      }
    rescue StandardError => e
      AppLogger.warn('api_sports_rugby_normalize', message: e.message)
      nil
    end

    FINAL_CODES     = %w[FT AOT].freeze
    LIVE_CODES      = %w[H1 HT H2 OT BT].freeze
    POSTPONED_CODES = %w[POST CANC ABD].freeze

    def map_status(code)
      return 'scheduled'  if code.nil?
      return 'final'      if FINAL_CODES.include?(code)
      return 'live'       if LIVE_CODES.include?(code)
      return 'postponed'  if POSTPONED_CODES.include?(code)
      'scheduled'
    end
  end
end
