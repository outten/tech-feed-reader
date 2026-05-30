require 'json'
require 'net/http'
require 'uri'

# STUFF #73 — Formula 1 data source. Jolpica is the community-maintained
# successor to the original Ergast API (`ergast.com`, retired April 2025).
# Same JSON shape; same URLs minus the host. No auth, no key, generous
# rate limits (~4 req/s burst, soft cap at 4M/day).
#
# Coverage:
#   - season(year)                 → races for the season
#   - season_results(year)         → finished races with podium + winner
#   - constructors / drivers       → not implemented in MVP
#
# Match-shape note: F1 races don't map cleanly onto our
# `sports_matches(home_team_id, away_team_id)` schema. We insert each
# race with both team FKs nil; venue + period carry the round info
# ("Round 7 — Monaco Grand Prix").
#
# See:
#   - http://api.jolpi.ca/ergast/ (homepage + docs)
#   - https://github.com/jolpica/jolpica-f1
module Providers
  module JolpicaF1
    BASE = 'https://api.jolpi.ca/ergast/f1'.freeze
    USER_AGENT = 'tech-feed-reader/1.0 (+https://feeder.tmoneystuff.com)'.freeze

    Race = Struct.new(:season, :round, :race_name, :circuit_name, :country,
                      :scheduled_at, :status, :winner_full_name, keyword_init: true)

    module_function

    # Returns Array<Race> for every round of the given season.
    # On HTTP / parse failure returns []. Logs via AppLogger.
    def season(year, http_get: nil)
      url      = "#{BASE}/#{year}.json"
      response = (http_get || method(:default_http_get)).call(url)
      return [] unless response.code.to_s == '200'

      data   = JSON.parse(response.body)
      races  = data.dig('MRData', 'RaceTable', 'Races') || []
      out    = races.flat_map { |r| normalize_race(r, season: year) }.compact
      AppLogger.info('jolpica_f1_season_done', year: year, count: out.length)
      out
    rescue JSON::ParserError => e
      AppLogger.error('jolpica_f1_season', status: :parse_error, message: e.message)
      []
    rescue StandardError => e
      AppLogger.error('jolpica_f1_season', status: :error, class: e.class.name, message: e.message)
      []
    end

    # Returns Array<Race> for completed races only — pulls /<year>/results
    # which is shorter than the season list but includes podium results.
    # Used to backfill `home_score` / winner when promoting a race row
    # from scheduled → final.
    def season_results(year, http_get: nil)
      url      = "#{BASE}/#{year}/results.json"
      response = (http_get || method(:default_http_get)).call(url)
      return [] unless response.code.to_s == '200'

      data   = JSON.parse(response.body)
      races  = data.dig('MRData', 'RaceTable', 'Races') || []
      out    = races.flat_map { |r| normalize_race(r, season: year, with_results: true) }.compact
      AppLogger.info('jolpica_f1_results_done', year: year, count: out.length)
      out
    rescue JSON::ParserError => e
      AppLogger.error('jolpica_f1_results', status: :parse_error, message: e.message)
      []
    rescue StandardError => e
      AppLogger.error('jolpica_f1_results', status: :error, class: e.class.name, message: e.message)
      []
    end

    def normalize_race(r, season:, with_results: false)
      circuit_name = r.dig('Circuit', 'circuitName')
      country      = r.dig('Circuit', 'Location', 'country')
      date_str     = [r['date'], r['time']].compact.join('T').sub(/Z?\z/, 'Z')
      winner       = nil
      status       = 'scheduled'
      if with_results
        top = (r['Results'] || []).find { |row| row['position'].to_i == 1 }
        if top
          winner = [top.dig('Driver', 'givenName'), top.dig('Driver', 'familyName')].compact.join(' ').strip
          status = 'final'
        end
      else
        # Heuristic: races with a date in the past = final. Date-only
        # comparison (no time precision needed for finality).
        begin
          status = Date.parse(r['date']) < Date.today ? 'final' : 'scheduled' if r['date']
        rescue ArgumentError
          status = 'scheduled'
        end
      end
      Race.new(
        season:           season.to_i,
        round:            r['round'].to_i,
        race_name:        r['raceName'],
        circuit_name:     circuit_name,
        country:          country,
        scheduled_at:     date_str.empty? ? nil : date_str,
        status:           status,
        winner_full_name: winner
      )
    rescue StandardError => e
      AppLogger.warn('jolpica_f1_normalize_skipped', round: r['round'], message: e.message)
      nil
    end

    def default_http_get(url)
      uri  = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.read_timeout = 8
      req  = Net::HTTP::Get.new(uri.request_uri)
      req['User-Agent'] = USER_AGENT
      req['Accept']     = 'application/json'
      http.request(req)
    end
  end
end
