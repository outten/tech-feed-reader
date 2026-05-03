require 'sidekiq'

# Shared Sidekiq configuration loaded by both the web process (when it
# enqueues jobs / mounts Sidekiq::Web) and the worker process (started
# via `make sidekiq`). Centralising here keeps the Redis URL definition
# in one place; pass REDIS_URL in the env to override the default.
module SidekiqConfig
  REDIS_URL = ENV['REDIS_URL'] || 'redis://localhost:6379/0'

  Sidekiq.configure_server do |config|
    config.redis = { url: REDIS_URL }
  end

  Sidekiq.configure_client do |config|
    config.redis = { url: REDIS_URL }
  end
end
