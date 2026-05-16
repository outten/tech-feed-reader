require 'json'
require 'rack/request'

# Per-IP throttling for credential-stuffing-vulnerable + cost-sensitive
# routes. Thread-safe in-process fixed-window counter — sufficient for
# a single-container deploy. Counts reset on app restart (intentional:
# if the process restarts, the attacker reset too).
#
# Mounted in the Rack::Builder block at the bottom of app/main.rb. The
# spec suite uses Rack::Test against the bare TechFeedReader class, so
# specs bypass this middleware automatically — no need for a test-env
# kill switch.
#
# Defense-in-depth on top of: WebAuthn challenges (which already block
# trivial replay) and LlmGuard (which bounds Anthropic spend). This
# layer protects against credential-stuffing volume and against a
# misbehaving client hammering /chat (where rapid retries would
# otherwise consume tokens up to the LlmGuard budget every minute).
class RateLimiter
  RULES = [
    # Auth — keep these tight. A real user retries 2-3 times max.
    { match: ->(req) { req.post? && req.path == '/sign-in' },              limit: 10, window: 300 },
    { match: ->(req) { req.post? && req.path == '/sign-up' },              limit: 5,  window: 300 },
    { match: ->(req) { req.post? && req.path.start_with?('/api/auth/') }, limit: 20, window: 300 },

    # Chat — extra brake above LlmGuard so a runaway client can't
    # exhaust the per-user daily quota in 60 seconds.
    { match: ->(req) { req.post? && req.path == '/chat' },                 limit: 60, window: 60 }
  ].freeze

  RESPONSE_HEADERS = { 'Content-Type' => 'application/json' }.freeze

  def initialize(app)
    @app     = app
    @mutex   = Mutex.new
    @buckets = {}
  end

  def call(env)
    req  = Rack::Request.new(env)
    rule = RULES.find { |r| r[:match].call(req) }
    return @app.call(env) unless rule

    if throttled?(req.ip, req.path, rule)
      retry_after = rule[:window].to_s
      return [
        429,
        RESPONSE_HEADERS.merge('Retry-After' => retry_after),
        [JSON.generate(error: 'rate-limited',
                       message: "Too many requests. Wait #{retry_after}s and try again.")]
      ]
    end

    @app.call(env)
  end

  private

  def throttled?(ip, path, rule)
    key = "#{ip}:#{path}"
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @mutex.synchronize do
      bucket = @buckets[key]
      if bucket.nil? || now - bucket[:start] >= rule[:window]
        @buckets[key] = { count: 1, start: now }
        return false
      end
      bucket[:count] += 1
      bucket[:count] > rule[:limit]
    end
  end
end
