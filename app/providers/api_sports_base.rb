require 'json'
require 'net/http'
require 'uri'

# STUFF #74 — api-sports.io shared HTTP plumbing. Each sport lives at
# its own subdomain (`v3.football.api-sports.io`,
# `v1.basketball.api-sports.io`, etc.) but the auth header
# (`x-apisports-key`) and response envelope shape (`{response: [...],
# results: N, errors: {...}, paging: {...}}`) are consistent.
#
# Subclass with `class Foo; include Providers::ApiSportsBase; HOST = '...'
# end` and call `get('/path', query: {...})` — returns the parsed
# `response` array on 200, [] on any failure (logged via AppLogger).
#
# Free tier: 100 req/day. Pro: 7,500/day at $10/mo. The base layer
# logs rate-limit headers after every call so the operator can spot
# upcoming caps from production logs.
module Providers
  module ApiSportsBase
    USER_AGENT = 'tech-feed-reader/1.0 (+https://feeder.tmoneystuff.com)'.freeze

    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      # `path` like '/fixtures' (no leading host). `query` like
      # { league: 39, season: 2026 }. Returns the `response` array
      # (or top-level value when it isn't an array). Returns []
      # on any failure.
      def get(path, query: {}, http_get: nil)
        key = ENV['API_SPORTS_KEY'].to_s
        if key.empty?
          AppLogger.warn('api_sports_skip', sport: self::HOST, reason: 'no_key')
          return []
        end

        url = build_url(path, query)
        response = (http_get || method(:default_http_get)).call(url, key)
        log_quota(response)

        unless response.code.to_s == '200'
          AppLogger.warn('api_sports_non_200', sport: self::HOST,
                                                path: path, status: response.code)
          return []
        end

        body = JSON.parse(response.body)
        if (errs = body['errors']).is_a?(Hash) && errs.any?
          AppLogger.warn('api_sports_errors', sport: self::HOST, errors: errs)
          return []
        end
        Array(body['response'])
      rescue JSON::ParserError => e
        AppLogger.error('api_sports', sport: self::HOST, status: :parse_error,
                                       message: e.message)
        []
      rescue StandardError => e
        AppLogger.error('api_sports', sport: self::HOST, status: :error,
                                       class: e.class.name, message: e.message)
        []
      end

      def build_url(path, query)
        qs = query.empty? ? '' : '?' + URI.encode_www_form(query)
        "https://#{self::HOST}#{path}#{qs}"
      end

      def default_http_get(url, key)
        uri  = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 10
        req = Net::HTTP::Get.new(uri.request_uri)
        req['x-apisports-key'] = key
        req['User-Agent']      = USER_AGENT
        req['Accept']          = 'application/json'
        http.request(req)
      end

      def log_quota(response)
        return unless response.respond_to?(:[])
        remaining = response['x-ratelimit-requests-remaining']
        return unless remaining
        AppLogger.debug('api_sports_quota', sport: self::HOST, remaining: remaining)
      end
    end
  end
end
