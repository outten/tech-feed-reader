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
  # any Redis/serialization error.
  #
  # marshal: false (default) → JSON. Only cache JSON-round-trippable data
  #   (primitives, arrays/hashes with STRING keys — DB rows are fine).
  # marshal: true → Marshal, for plain Ruby structures JSON can't
  #   round-trip (e.g. symbol-keyed hashes like TopicClusters output).
  #   Redis is trusted (same store as the job queue); a bad/stale payload
  #   raises and we just recompute.
  def fetch(key, ttl:, marshal: false)
    return yield unless enabled?

    raw = safe_get(key)
    if raw
      begin
        return marshal ? Marshal.load(raw.b) : JSON.parse(raw)
      rescue StandardError
        # Corrupt / incompatible entry — fall through and recompute.
      end
    end

    value = yield
    safe_set(key, value, ttl, marshal)
    value
  end

  def delete(*keys)
    keys = keys.flatten.compact
    return if keys.empty?
    client.call('DEL', *keys)
  rescue StandardError
    nil
  end

  # Unconditionally write `value` with `ttl` (a force-refresh — bypasses the
  # read in `fetch`). Used by cache-warming jobs that recompute proactively.
  # No-op when caching is disabled; swallows write errors like safe_set.
  def write(key, value, ttl:, marshal: false)
    return value unless enabled?
    safe_set(key, value, ttl, marshal)
    value
  end

  class << self
    private

    def safe_get(key)
      client.call('GET', key)
    rescue StandardError => e
      AppLogger.warn('cache_get_failed', key: key, message: e.message)
      nil
    end

    def safe_set(key, value, ttl, marshal = false)
      payload = marshal ? Marshal.dump(value) : JSON.generate(value)
      client.call('SET', key, payload, 'EX', ttl)
    rescue StandardError => e
      AppLogger.warn('cache_set_failed', key: key, message: e.message)
    end
  end
end
