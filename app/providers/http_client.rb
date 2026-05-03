require 'net/http'
require 'uri'

# Shared HTTP layer used by FeedFetcher and (later) the readability /
# archive providers. Wraps Net::HTTP with:
#
#   - a single User-Agent so publishers can identify us in logs
#   - retry-with-backoff on transient network failures (timeouts, EOF,
#     resets) — three attempts with linear backoff
#   - cache-friendly headers passed through verbatim from the caller
#     (If-Modified-Since, If-None-Match) so 304 responses are honoured
#   - 301/302/307/308 redirect following with a hop limit, so feeds
#     that publish a forwarding URL (e.g. simplecast → simplecastaudio)
#     still get fetched. Conditional-GET headers are dropped on the
#     redirected request because the new URL has its own etag space.
#
# Test env raises on any unstubbed call so an accidental network hit
# during a spec run fails loudly instead of flaking the suite.
module Providers
  module HttpClient
    USER_AGENT      = 'tech-feed-reader/0.1 (+https://github.com/outten/tech-feed-reader)'.freeze
    DEFAULT_TIMEOUT = 30  # seconds (open + read)
    MAX_RETRIES     = 2
    BACKOFF         = 1.0 # seconds, multiplied by attempt number
    MAX_REDIRECTS   = 5

    TRANSIENT_ERRORS = [
      Net::OpenTimeout, Net::ReadTimeout,
      Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::EHOSTUNREACH,
      EOFError, SocketError, IOError
    ].freeze

    module_function

    # GET a URL. Returns the Net::HTTPResponse (any status code — 304 and
    # 4xx/5xx are not retried; only transport-layer failures are).
    # `headers` is a flat hash; nil/empty values are dropped so
    # `{'If-Modified-Since' => nil}` doesn't produce a malformed header.
    #
    # 3xx redirects are followed up to MAX_REDIRECTS hops; the loop
    # raises if the limit is exceeded, and the final non-redirect
    # response is returned to the caller. Conditional-GET headers are
    # only sent on the first hop — they belong to the original URL's
    # cache state, not the redirect target.
    def get(url, headers: {}, timeout: DEFAULT_TIMEOUT)
      check_test_env!

      current_url = url
      hops        = 0
      first_hop   = true

      loop do
        response = perform_get(current_url, headers: first_hop ? headers : {}, timeout: timeout)
        return response unless redirect?(response)

        hops += 1
        raise "Too many redirects (>#{MAX_REDIRECTS}) starting from #{url}" if hops > MAX_REDIRECTS

        location = response['Location'].to_s
        raise "Redirect with no Location header from #{current_url}" if location.empty?

        current_url = URI.join(current_url, location).to_s
        first_hop   = false
      end
    end

    def perform_get(url, headers:, timeout:)
      uri = URI.parse(url)
      raise ArgumentError, "Unsupported URL scheme: #{uri.scheme}" unless %w[http https].include?(uri.scheme)

      req = Net::HTTP::Get.new(uri.request_uri)
      req['User-Agent'] = USER_AGENT
      headers.each do |k, v|
        next if v.nil? || v.to_s.empty?
        req[k.to_s] = v.to_s
      end

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = uri.scheme == 'https'
      http.open_timeout = timeout
      http.read_timeout = timeout

      with_retries do
        http.start { |h| h.request(req) }
      end
    end

    def redirect?(response)
      %w[301 302 307 308].include?(response.code.to_s)
    end

    class << self
      private

      def with_retries
        attempt = 0
        begin
          yield
        rescue *TRANSIENT_ERRORS
          attempt += 1
          if attempt <= MAX_RETRIES
            sleep BACKOFF * attempt unless ENV['RACK_ENV'] == 'test'
            retry
          end
          raise
        end
      end

      def check_test_env!
        return unless ENV['RACK_ENV'] == 'test' && !ENV['ALLOW_HTTP']
        raise 'HTTP calls disabled in test env (set ALLOW_HTTP=1 to opt in, or stub Net::HTTP)'
      end
    end
  end
end
