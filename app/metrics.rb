require 'prometheus/client'
require 'prometheus/client/formats/text'

# Process-local Prometheus registry. The web process and the Sidekiq
# worker process each have their own — that's normal for Prometheus
# Ruby clients (no shared store; scrape both targets if needed).
#
# Metric names are prefixed `tfr_` (tech-feed-reader) so they're
# unambiguous in a multi-app dashboard.
module Metrics
  REGISTRY = Prometheus::Client.registry

  # ---- Counters ------------------------------------------------------
  HTTP_REQUESTS = REGISTRY.counter(
    :tfr_http_requests_total,
    docstring: 'Total HTTP requests by method, route, and status code.',
    labels:    %i[method route status]
  )

  FEED_FETCHES = REGISTRY.counter(
    :tfr_feed_fetches_total,
    docstring: 'Feed fetch attempts grouped by terminal status.',
    labels:    %i[status]
  )

  ARTICLES_IMPORTED = REGISTRY.counter(
    :tfr_articles_imported_total,
    docstring: 'Articles inserted into the DB by the import pipeline.'
  )

  SUMMARIES_GENERATED = REGISTRY.counter(
    :tfr_summaries_generated_total,
    docstring: 'Summaries generated, by kind (extractive | llm).',
    labels:    %i[kind]
  )

  SIDEKIQ_JOBS = REGISTRY.counter(
    :tfr_sidekiq_jobs_total,
    docstring: 'Sidekiq jobs processed by class and terminal status.',
    labels:    %i[worker status]
  )

  # ---- Histograms ----------------------------------------------------
  # Buckets are in seconds. Defaults from the prometheus-client gem cover
  # the typical web-app latency range; we keep them stock to stay
  # compatible with shared dashboards.
  HTTP_DURATION = REGISTRY.histogram(
    :tfr_http_request_duration_seconds,
    docstring: 'HTTP request duration in seconds.',
    labels:    %i[method route]
  )

  FEED_FETCH_DURATION = REGISTRY.histogram(
    :tfr_feed_fetch_duration_seconds,
    docstring: 'Time to fetch + parse one feed, in seconds.'
  )

  SIDEKIQ_JOB_DURATION = REGISTRY.histogram(
    :tfr_sidekiq_job_duration_seconds,
    docstring: 'Sidekiq job duration in seconds.',
    labels:    %i[worker]
  )

  # ---- Gauges (refreshed on every /metrics scrape) -------------------
  FEEDS_SUBSCRIBED = REGISTRY.gauge(
    :tfr_feeds_subscribed,
    docstring: 'Total subscribed feeds.'
  )

  ARTICLES_TOTAL = REGISTRY.gauge(
    :tfr_articles_total,
    docstring: 'Total articles in the DB.'
  )

  SIDEKIQ_QUEUE_DEPTH = REGISTRY.gauge(
    :tfr_sidekiq_queue_depth,
    docstring: 'Current depth of the Sidekiq default queue.'
  )

  SIDEKIQ_WORKERS = REGISTRY.gauge(
    :tfr_sidekiq_workers,
    docstring: 'Number of Sidekiq processes registered with Redis.'
  )

  UPTIME = REGISTRY.gauge(
    :tfr_uptime_seconds,
    docstring: 'Process uptime since boot, in seconds.'
  )

  module_function

  # Collapse high-cardinality URL params into stable labels — e.g.
  # /article/abc123 → /article/:uid. Without this every article uid
  # becomes its own time series and Prometheus melts.
  def normalize_route(path)
    p = path.to_s
    p = p.sub(%r{\A/article/[^/?]+},          '/article/:uid')
    p = p.sub(%r{\A/admin/refresh/(?!all\b)[^/?]+}, '/admin/refresh/:id')
    p = p.sub(%r{\A/api/admin/refresh/(?!all\b)[^/?]+}, '/api/admin/refresh/:id')
    p = p.sub(%r{\A/api/feeds/\d+\b},         '/api/feeds/:id')
    p = p.sub(%r{\A/feeds/\d+/delete\b},      '/feeds/:id/delete')
    p = p.sub(%r{\A/topics/[^/?]+},           '/topics/:term')
    p = p.sub(%r{\A/tags/\d+/delete\b},       '/tags/:id/delete')
    p = p.sub(%r{\A/article/[^/?]+/(read|bookmark|archive|summarize(/llm)?|tag/\d+)},
              '/article/:uid/\1')
    p
  end
end
