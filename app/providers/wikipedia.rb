require 'json'
require 'net/http'
require 'uri'
require 'cgi'

# STUFF #73 — Wikipedia REST API.
#
# WMF guidelines we follow:
#   - User-Agent header identifying the application + contact URL
#     (required for any automated access; the API will rate-limit or
#     block requests with generic UAs)
#   - Use the REST API summary endpoint, not HTML scraping
#   - Cache responses so we don't hit Wikipedia on every page load
#     (cache lives on the sports_leagues row — see Wikipedia.refresh_for)
#
# The summary endpoint returns a small JSON envelope (title, extract,
# extract_html, thumbnail, content_urls) — ~5KB on average. Cached for
# 24h via the wikipedia_summary_fetched_at column.
#
# Reference: https://en.wikipedia.org/api/rest_v1/
module Providers
  module Wikipedia
    BASE = 'https://en.wikipedia.org/api/rest_v1'.freeze
    USER_AGENT = 'tech-feed-reader/1.0 (+https://feeder.tmoneystuff.com; ops@feeder.tmoneystuff.com)'.freeze
    CACHE_TTL_SECONDS = 24 * 60 * 60

    Summary = Struct.new(:title, :extract, :extract_html, :thumbnail_url,
                         :page_url, keyword_init: true)

    module_function

    # Fetch the page summary for the given Wikipedia article title.
    # Returns a Summary struct, or nil on any failure (page missing,
    # network error, parse error). Wikipedia titles use underscores
    # OR spaces — we normalize to spaces and let the REST API encode.
    def summary(title, http_get: nil)
      return nil if title.to_s.strip.empty?

      # Wikipedia REST path segments need %20-encoded spaces, not the
      # `+` shape CGI.escape emits for query strings.
      encoded = CGI.escape(title.to_s.strip.tr('_', ' ')).gsub('+', '%20')
      url     = "#{BASE}/page/summary/#{encoded}"
      response = (http_get || method(:default_http_get)).call(url)
      return nil unless response.code.to_s == '200'

      data = JSON.parse(response.body)
      Summary.new(
        title:         data['title'],
        extract:       data['extract'],
        extract_html:  data['extract_html'],
        thumbnail_url: data.dig('thumbnail', 'source'),
        page_url:      data.dig('content_urls', 'desktop', 'page')
      )
    rescue JSON::ParserError => e
      AppLogger.error('wikipedia_summary', status: :parse_error, title: title, message: e.message)
      nil
    rescue StandardError => e
      AppLogger.error('wikipedia_summary', status: :error, title: title,
                                            class: e.class.name, message: e.message)
      nil
    end

    # Cached fetch for a sports_leagues row. Returns the row hash with
    # the cache columns populated (or unchanged if cache is fresh).
    # No-op when wikipedia_title is null (catalog hasn't declared one
    # for this league).
    def refresh_for_league(league, http_get: nil, now: Time.now)
      title = league['wikipedia_title']
      return league if title.to_s.empty?

      fetched_at = parse_time(league['wikipedia_summary_fetched_at'])
      if league['wikipedia_summary'].to_s != '' && fetched_at && (now - fetched_at) < CACHE_TTL_SECONDS
        return league
      end

      result = summary(title, http_get: http_get)
      return league unless result

      payload = {
        title:         result.title,
        extract:       result.extract,
        extract_html:  result.extract_html,
        thumbnail_url: result.thumbnail_url,
        page_url:      result.page_url
      }
      SportsLeaguesStore.set_wikipedia_summary!(league['id'], payload.to_json, now: now)
      SportsLeaguesStore.find(league['id'])
    end

    def parse_time(value)
      return nil if value.nil? || value.to_s.empty?
      Time.parse(value.to_s)
    rescue ArgumentError
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
