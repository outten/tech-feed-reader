require_relative 'metrics'

# Rack middleware that times every HTTP request and bumps the
# `tfr_http_requests_total` counter + `tfr_http_request_duration_seconds`
# histogram. Mounted ahead of TechFeedReader in app/main.rb's Rack
# builder, so /metrics itself is observed too (Prometheus scrapers do
# scrape that route).
#
# Path normalization happens in Metrics.normalize_route so dynamic
# segments collapse to :uid / :id labels — otherwise the cardinality
# would explode (every article uid becomes its own time series).
class MetricsMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    status, headers, body = @app.call(env)
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

    method = env['REQUEST_METHOD'].to_s
    route  = Metrics.normalize_route(env['PATH_INFO'])

    Metrics::HTTP_REQUESTS.increment(
      labels: { method: method, route: route, status: status.to_s }
    )
    Metrics::HTTP_DURATION.observe(
      duration,
      labels: { method: method, route: route }
    )

    [status, headers, body]
  end
end
