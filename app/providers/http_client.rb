require 'net/http'
require 'uri'
require 'ipaddr'
require 'resolv'

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

    # SSRF guard. Feed + article URLs are user-supplied, so without this a
    # user could add a "feed" pointing at the cloud-metadata endpoint
    # (169.254.169.254), localhost, or an internal service and have the
    # server fetch it — and the readability path renders the fetched body
    # straight into article content. We refuse any URL that resolves into a
    # private / loopback / link-local / reserved range. Checked on every hop
    # (perform_get runs per redirect), so a public URL that 302s inward is
    # blocked too. Residual risk: DNS rebinding between this check and the
    # socket connect — acceptable for a first pass; revisit by pinning the
    # resolved IP if it ever matters.
    BLOCKED_RANGES = %w[
      0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
      172.16.0.0/12 192.0.0.0/24 192.168.0.0/16 198.18.0.0/15
      ::1/128 fc00::/7 fe80::/10
    ].map { |r| IPAddr.new(r) }.freeze

    SsrfError = Class.new(StandardError)

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
      guard_public_host!(uri.host)

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

    # Raise SsrfError unless every address `host` resolves to is publicly
    # routable. A literal IP is checked directly; a hostname is DNS-resolved
    # and every returned address must pass (so a name with one internal A
    # record is rejected).
    def guard_public_host!(host)
      raise SsrfError, 'Refusing to fetch a URL with no host' if host.to_s.empty?

      addrs = resolve_addresses(host)
      raise SsrfError, "Cannot resolve host: #{host}" if addrs.empty?

      bad = addrs.find { |ip| blocked_ip?(ip) }
      raise SsrfError, "Refusing to fetch non-public address #{bad} (host #{host})" if bad
    end

    def resolve_addresses(host)
      literal = (IPAddr.new(host) rescue nil)
      return [literal] if literal

      Resolv.getaddresses(host).filter_map { |a| IPAddr.new(a) rescue nil }
    rescue StandardError
      []
    end

    def blocked_ip?(ip)
      # Normalise IPv4-mapped IPv6 (::ffff:127.0.0.1) to its IPv4 form so a
      # mapped loopback/private address can't slip past the v4 ranges.
      ip = ip.native if ip.respond_to?(:ipv4_mapped?) && ip.ipv4_mapped?
      BLOCKED_RANGES.any? { |range| range.include?(ip) }
    rescue StandardError
      true # fail closed on anything we can't classify
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
