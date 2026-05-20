require_relative 'logger'
require_relative 'pageview_section'
require_relative 'pageviews_store'

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
#
# STUFF #48.1 — also persists one row per dynamic GET request into
# the `pageviews` table for the admin analytics page. Static-asset
# noise (/health, /metrics, css/js) is filtered by
# PageviewSection.ignore?. Persist errors are rescued (we'd rather
# log + serve the request than 500 because the DB hiccupped on
# the side-effect insert).
module RequestLogMiddleware
  class App
    def initialize(app)
      @app = app
    end

    def call(env)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      status, headers, body = @app.call(env)
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

      path = env['PATH_INFO']
      payload = {
        method:     env['REQUEST_METHOD'],
        path:       path,
        status:     status,
        latency_ms: latency_ms,
        ip:         env['HTTP_X_FORWARDED_FOR'] || env['REMOTE_ADDR']
      }
      query = env['QUERY_STRING'].to_s
      payload[:query] = query unless query.empty?
      ua = env['HTTP_USER_AGENT'].to_s
      payload[:user_agent] = ua unless ua.empty?

      AppLogger.info('http_request', **payload)

      record_pageview(env, path, status)

      [status, headers, body]
    end

    private

    # Skip noise paths + non-GETs (POST/PUT/DELETE aren't pageviews).
    # Pulls user_id off the Rack session — set by Auth::Helpers#sign_in!
    # — so signed-in pageviews can be attributed; nil for anonymous.
    # All errors are swallowed so the persist side-effect can't fail
    # a request. Real failures (schema not migrated, PG down) still
    # show up in the structured log via the logger.warn line.
    def record_pageview(env, path, status)
      return unless env['REQUEST_METHOD'] == 'GET'
      return if PageviewSection.ignore?(path)

      session = env['rack.session']
      user_id = session && session[:user_id]
      PageviewsStore.record!(
        user_id: user_id,
        path:    path,
        section: PageviewSection.for_path(path),
        status:  status
      )
    rescue StandardError => e
      AppLogger.warn('pageview_persist_failed', path: path, message: e.message)
    end
  end
end
