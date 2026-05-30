require_relative 'api_sports_base'

# STUFF #74 — NPB (Japan) + KBO (Korea) coverage. ESPN doesn't expose
# these leagues; api-sports does.
# Reference: https://api-sports.io/documentation/baseball/v1
module Providers
  module ApiSportsBaseball
    include ApiSportsBase
    HOST = 'v1.baseball.api-sports.io'.freeze

    NPB_LEAGUE_ID = 2  # Japan
    KBO_LEAGUE_ID = 5  # Korea

    module_function

    def fixtures(league_id:, season: Date.today.year, http_get: nil)
      raw = ApiSportsBaseball.get('/games',
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
        home_score:            g.dig('scores', 'home', 'total'),
        away_score:            g.dig('scores', 'away', 'total'),
        venue:                 nil
      }
    rescue StandardError => e
      AppLogger.warn('api_sports_baseball_normalize', message: e.message)
      nil
    end

    FINAL_CODES     = %w[FT].freeze
    LIVE_CODES      = %w[IN1 IN2 IN3 IN4 IN5 IN6 IN7 IN8 IN9].freeze
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
