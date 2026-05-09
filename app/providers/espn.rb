require 'json'
require_relative 'http_client'
require_relative '../logger'

# Sports Phase S4 — ESPN provider for structured match data.
#
# Uses ESPN's public-but-undocumented API endpoints (reverse-
# engineered, no auth, no documented rate limit). See
#   https://gist.github.com/akeaswaran/b48b02f1c94f873c6655e7129910fc3b
#   https://github.com/pseudo-r/Public-ESPN-API
#
# Wrap calls in a defensive layer so:
#   - Network errors don't crash the sync script — caller gets
#     an empty array + a logged warning.
#   - JSON shape changes upstream don't 500: each event is parsed
#     in isolation with rescue StandardError.
#
# Coverage in v1 (Phase S4):
#   - NFL  via /sports/football/nfl/teams/<id>/schedule
#   - NBA  via /sports/basketball/nba/teams/<id>/schedule
#   - MLS  via /sports/soccer/usa.1/teams/<id>/schedule
#   - International rugby via /sports/rugby/<league_id>/scoreboard
#     (team-schedule endpoint 500s for rugby; scoreboard works,
#     and the sync script filters to the followed teams).
#
# TheSportsDB integration deferred — their free key '3' is
# poisoned (every search returns Arsenal). Black Ferns + tennis
# structured data will land once a working provider is found OR
# the user's interest in those structured surfaces grows enough
# to justify the $9/mo Patreon key.
module Providers
  module ESPN
    BASE = 'https://site.api.espn.com/apis/site/v2/sports'.freeze

    # ESPN status code → our normalized status. The full ESPN set
    # has more codes (e.g. STATUS_DELAYED, STATUS_FORFEIT) but they
    # collapse cleanly into our 5-status taxonomy.
    STATUS_MAP = {
      'STATUS_SCHEDULED'        => 'scheduled',
      'STATUS_IN_PROGRESS'      => 'live',
      'STATUS_HALFTIME'         => 'live',
      'STATUS_END_PERIOD'       => 'live',
      'STATUS_FINAL'            => 'final',
      'STATUS_FULL_TIME'        => 'final',
      'STATUS_FULLTIME'         => 'final',
      'STATUS_FULL_PEN'         => 'final',
      'STATUS_END_OF_FIGHT'     => 'final',
      'STATUS_POSTPONED'        => 'postponed',
      'STATUS_RAIN_DELAY'       => 'postponed',
      'STATUS_CANCELED'         => 'cancelled',
      'STATUS_CANCELLED'        => 'cancelled',
      'STATUS_FORFEIT'          => 'cancelled'
    }.freeze

    # Normalized match shape — what stores accept upstream.
    Match = Struct.new(:external_id, :scheduled_at, :status,
                       :home_team_external_id, :home_team_name,
                       :away_team_external_id, :away_team_name,
                       :home_score, :away_score, :period, :venue,
                       keyword_init: true)

    module_function

    # Per-team season schedule. Works for NFL, NBA, MLS. Rugby
    # 500s on this endpoint — use league_scoreboard there.
    #
    # `sport_path` is the ESPN sport path (e.g. 'football/nfl').
    # `team_external_id` is the numeric ESPN team id.
    #
    # Returns an array of Match structs. Empty on HTTP/parse failure.
    def team_schedule(sport_path:, team_external_id:, http_get: nil)
      url = "#{BASE}/#{sport_path}/teams/#{team_external_id}/schedule"
      AppLogger.debug('espn_team_schedule_start', sport_path: sport_path, team: team_external_id)
      response = (http_get || method(:default_http_get)).call(url)
      return [] unless response.code.to_s == '200'

      data = JSON.parse(response.body)
      events = Array(data['events'])
      out = events.flat_map { |ev| normalize_event(ev) }.compact
      AppLogger.info('espn_team_schedule_done', sport_path: sport_path, team: team_external_id, count: out.length)
      out
    rescue JSON::ParserError => e
      AppLogger.error('espn_team_schedule', status: :parse_error, message: e.message)
      []
    rescue StandardError => e
      AppLogger.error('espn_team_schedule', status: :error, class: e.class.name, message: e.message)
      []
    end

    # League-level scoreboard. Used for sports where team_schedule
    # 500s (rugby). `dates` is an optional ESPN date filter, e.g.
    # '20251020' or '20251020-20251030'. Without it, ESPN returns
    # the league's current week (could be empty for off-season).
    #
    # Caller filters to followed teams in the sync script.
    def league_scoreboard(sport_path:, dates: nil, http_get: nil)
      url = "#{BASE}/#{sport_path}/scoreboard"
      url += "?dates=#{dates}" if dates
      AppLogger.debug('espn_league_scoreboard_start', sport_path: sport_path, dates: dates)
      response = (http_get || method(:default_http_get)).call(url)
      return [] unless response.code.to_s == '200'

      data = JSON.parse(response.body)
      events = Array(data['events'])
      out = events.flat_map { |ev| normalize_event(ev) }.compact
      AppLogger.info('espn_league_scoreboard_done', sport_path: sport_path, dates: dates, count: out.length)
      out
    rescue JSON::ParserError => e
      AppLogger.error('espn_league_scoreboard', status: :parse_error, message: e.message)
      []
    rescue StandardError => e
      AppLogger.error('espn_league_scoreboard', status: :error, class: e.class.name, message: e.message)
      []
    end

    # ESPN event JSON → Match struct. Returns [Match] on success,
    # [] when the event shape is unexpected (so flat_map drops it).
    # Rescues per-event so one weird row doesn't poison the batch.
    def normalize_event(ev)
      return [] unless ev.is_a?(Hash)
      comp = (ev['competitions'] || []).first
      return [] unless comp

      competitors = comp['competitors'] || []
      home = competitors.find { |c| c['homeAway'] == 'home' } || competitors[0]
      away = competitors.find { |c| c['homeAway'] == 'away' } || competitors[1]
      return [] unless home && away

      status_raw = ev.dig('status', 'type', 'name') || comp.dig('status', 'type', 'name')
      [
        Match.new(
          external_id:           ev['id'].to_s,
          scheduled_at:          ev['date'],
          status:                STATUS_MAP[status_raw] || 'scheduled',
          home_team_external_id: home.dig('team', 'id').to_s,
          home_team_name:        home.dig('team', 'displayName') || home.dig('team', 'name'),
          away_team_external_id: away.dig('team', 'id').to_s,
          away_team_name:        away.dig('team', 'displayName') || away.dig('team', 'name'),
          home_score:            extract_score(home),
          away_score:            extract_score(away),
          period:                ev.dig('status', 'type', 'shortDetail') || nil,
          venue:                 comp.dig('venue', 'fullName')
        )
      ]
    rescue StandardError => e
      AppLogger.warn('espn_normalize', status: :skip, message: e.message,
                                        event_id: (ev.is_a?(Hash) ? ev['id'] : nil))
      []
    end

    def cast_int(v)
      return nil if v.nil? || v == ''
      Integer(v.to_s)
    rescue ArgumentError
      nil
    end

    # ESPN's competitor score is sometimes a flat string ("24"),
    # sometimes a nested object ({value: 24.0, displayValue: "24"}).
    # Pull the display value when present, fall back to the whole
    # field cast to int.
    def extract_score(competitor)
      raw = competitor['score']
      case raw
      when Hash    then cast_int(raw['displayValue'] || raw['value'])
      when nil, '' then nil
      else              cast_int(raw)
      end
    end

    class << self
      private

      def default_http_get(url)
        Providers::HttpClient.get(url)
      end
    end
  end
end
