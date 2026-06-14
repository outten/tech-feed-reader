require 'json'
require 'redis-client'
require_relative 'sidekiq_config'
require_relative 'logger'

# Tiny Redis-backed cache for expensive per-request computation (the
# For-You ranking, for now). Separate from the Sidekiq job queue but
# reuses the same Redis (SidekiqConfig::REDIS_URL).
#
# Contract: caching must NEVER break a page render. Any Redis error on
# GET, a malformed cached value, or a SET failure all fall back to
# computing the value fresh. Values are JSON-serialized, so only cache
# JSON-round-trippable data (arrays / hashes of primitives) — not full
# article rows with per-user state.
module Cache
  module_function

  def client
    # redis-client's built-in pool (uses the connection_pool gem). Small
    # pool + short timeout so a wedged Redis degrades fast, not slow.
    @client ||= RedisClient.config(url: SidekiqConfig::REDIS_URL).new_pool(timeout: 1, size: 5)
  end

  # Off in the test env: specs reset the DB per example but Redis isn't,
  # so a shared cache key would leak rankings across examples. (CI has no
  # Redis anyway.) The cache logic itself is covered by cache_spec.rb.
  def enabled?
    ENV['RACK_ENV'] != 'test'
  end

  # Return the cached value for `key`, or run `block`, cache its result
  # for `ttl` seconds, and return it. Degrades to a plain `block` call on
  # any Redis/JSON error.
  def fetch(key, ttl:)
    return yield unless enabled?

    raw = safe_get(key)
    if raw
      begin
        return JSON.parse(raw)
      rescue JSON::ParserError
        # Corrupt entry — fall through and recompute.
      end
    end

    value = yield
    safe_set(key, value, ttl)
    value
  end

  def delete(*keys)
    keys = keys.flatten.compact
    return if keys.empty?
    client.call('DEL', *keys)
  rescue StandardError
    nil
  end

  class << self
    private

    def safe_get(key)
      client.call('GET', key)
    rescue StandardError => e
      AppLogger.warn('cache_get_failed', key: key, message: e.message)
      nil
    end

    def safe_set(key, value, ttl)
      client.call('SET', key, JSON.generate(value), 'EX', ttl)
    rescue StandardError => e
      AppLogger.warn('cache_set_failed', key: key, message: e.message)
    end
  end
end
