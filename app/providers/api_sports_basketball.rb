require_relative 'api_sports_base'

# STUFF #74 — supplements ESPN's NBA / WNBA with NCAA + EuroLeague +
# any other basketball league we have in catalog beyond ESPN's reach.
# Reference: https://api-sports.io/documentation/basketball/v1
module Providers
  module ApiSportsBasketball
    include ApiSportsBase
    HOST = 'v1.basketball.api-sports.io'.freeze

    # API-Sports canonical league IDs. Not exhaustive — operator can
    # add more by hitting /leagues and grabbing the id from the JSON.
    EUROLEAGUE_LEAGUE_ID = 120
    NCAA_LEAGUE_ID       = 116

    module_function

    def fixtures(league_id:, season: Date.today.year, http_get: nil)
      raw = ApiSportsBasketball.get('/games',
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
        venue:                 g['venue']
      }
    rescue StandardError => e
      AppLogger.warn('api_sports_basketball_normalize', message: e.message)
      nil
    end

    def standings(league_id:, season: Date.today.year, http_get: nil)
      raw = ApiSportsBasketball.get('/standings',
                                    query: { league: league_id, season: season },
                                    http_get: http_get)
      Array(raw).flat_map do |grp|
        Array(grp).map do |row|
          {
            team_external_id: row.dig('team', 'id').to_s,
            team_name:        row.dig('team', 'name'),
            team_logo:        row.dig('team', 'logo'),
            group_name:       row.dig('group', 'name'),
            position:         row['position']&.to_i,
            wins:             row.dig('games', 'win', 'total'),
            losses:           row.dig('games', 'lose', 'total'),
            points_for:       row.dig('points', 'for'),
            points_against:   row.dig('points', 'against'),
            points:           nil
          }
        end
      end
    rescue StandardError => e
      AppLogger.warn('api_sports_basketball_standings', message: e.message)
      []
    end

    FINAL_CODES     = %w[FT AOT].freeze
    LIVE_CODES      = %w[Q1 Q2 Q3 Q4 OT BT].freeze
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
