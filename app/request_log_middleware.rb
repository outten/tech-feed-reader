require_relative 'logger'

# Cosmetics 7 — Rack-level request logger. Sits ahead of Sinatra's
# static-file handler so it sees EVERY request, including
# /style.css, /global-player.js, etc. Sinatra's `after` filter fires
# only for dynamic routes; using a middleware is the only way to
# get full coverage.
#
# Emits one structured-JSON line per request:
#
#   {ts: ..., level: "info", event: "http_request",
#    method: "GET", path: "/articles", query: "state=unread",
#    status: 200, latency_ms: 12, ip: "127.0.0.1",
#    user_agent: "..."}
#
# query / user_agent are omitted when empty so jq pipelines stay
# tidy. Uses AppLogger.info (level INFO) so a downstream tail can
# filter to DEBUG-only for everything else without dropping
# request lines. The dev default is DEBUG anyway, so request
# lines surface either way in development.
module RequestLogMiddleware
  class App
    def initialize(app)
      @app = app
    end

    def call(env)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      status, headers, body = @app.call(env)
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

      payload = {
        method:     env['REQUEST_METHOD'],
        path:       env['PATH_INFO'],
        status:     status,
        latency_ms: latency_ms,
        ip:         env['HTTP_X_FORWARDED_FOR'] || env['REMOTE_ADDR']
      }
      query = env['QUERY_STRING'].to_s
      payload[:query] = query unless query.empty?
      ua = env['HTTP_USER_AGENT'].to_s
      payload[:user_agent] = ua unless ua.empty?

      AppLogger.info('http_request', **payload)

      [status, headers, body]
    end
  end
end
