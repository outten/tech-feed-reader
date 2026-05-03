require 'sidekiq'
require_relative 'sidekiq_metrics_middleware'

# Shared Sidekiq configuration loaded by both the web process (when it
# enqueues jobs / mounts Sidekiq::Web) and the worker process (started
# via `make sidekiq`). Centralising here keeps the Redis URL definition
# in one place; pass REDIS_URL in the env to override the default.
#
# The server middleware adds Prometheus metrics for every job
# (tfr_sidekiq_jobs_total + tfr_sidekiq_job_duration_seconds). The
# block only runs in the worker process — the web process doesn't
# install server middleware.
module SidekiqConfig
  REDIS_URL = ENV['REDIS_URL'] || 'redis://localhost:6379/0'

  Sidekiq.configure_server do |config|
    config.redis = { url: REDIS_URL }
    config.server_middleware do |chain|
      chain.add SidekiqMetricsMiddleware
    end
  end

  Sidekiq.configure_client do |config|
    config.redis = { url: REDIS_URL }
  end
end
