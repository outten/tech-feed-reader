require_relative 'api_sports_base'

# STUFF #74 — NHL + KHL coverage via api-sports.io. ESPN doesn't
# cover hockey at all; this is our only path to NHL data.
#
# Reference: https://api-sports.io/documentation/hockey/v1
module Providers
  module ApiSportsHockey
    include ApiSportsBase
    HOST = 'v1.hockey.api-sports.io'.freeze

    # API-Sports' canonical NHL league_id is 57. Used by sync wiring
    # so the catalog doesn't have to carry per-provider IDs.
    NHL_LEAGUE_ID = 57

    module_function

    # Returns Array<Hash> of normalized match rows for the league +
    # season window. Defaults to the current season.
    def fixtures(league_id:, season: Date.today.year, http_get: nil)
      raw = ApiSportsHockey.get('/games',
                                query: { league: league_id, season: season },
                                http_get: http_get)
      raw.map { |g| normalize_game(g) }.compact
    end

    def standings(league_id:, season: Date.today.year, http_get: nil)
      raw = ApiSportsHockey.get('/standings',
                                query: { league: league_id, season: season },
                                http_get: http_get)
      raw.flat_map { |grp| normalize_standings_group(grp) }
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
        venue:                 [g['venue'], g['country']&.dig('name')].compact.join(', ').then { |v| v.empty? ? nil : v }
      }
    rescue StandardError => e
      AppLogger.warn('api_sports_hockey_normalize', message: e.message)
      nil
    end

    # API-Sports standings come per-group (conference / division for
    # NHL). Each entry is { rank, team, points, games:{played,wins,
    # losses,...}, ... }.
    def normalize_standings_group(grp)
      Array(grp).map do |row|
        {
          team_external_id: row.dig('team', 'id').to_s,
          team_name:        row.dig('team', 'name'),
          team_logo:        row.dig('team', 'logo'),
          group_name:       row['group']&.dig('name'),
          position:         row['position']&.to_i,
          wins:             row.dig('games', 'win', 'total'),
          losses:           row.dig('games', 'lose', 'total'),
          points_for:       row.dig('goals', 'for'),
          points_against:   row.dig('goals', 'against'),
          points:           row['points']
        }
      end
    rescue StandardError => e
      AppLogger.warn('api_sports_hockey_normalize_standings', message: e.message)
      []
    end

    # Map api-sports status codes (FT, AOT, AP, NS, etc.) onto our
    # sports_matches status enum (scheduled / live / final /
    # postponed / cancelled).
    FINAL_CODES     = %w[FT AOT AP].freeze
    LIVE_CODES      = %w[Q1 Q2 Q3 OT BT P PST].freeze - %w[PST]
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

