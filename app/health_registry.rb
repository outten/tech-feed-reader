# Bounded ring buffer of feed-fetch observations. In-memory only —
# clears on process restart. Surfaces at /admin/health; the dashboard
# checks .degraded? to decide whether to show the "feeds are systematically
# failing" banner (e.g. user lost network, publisher killed an old RSS
# endpoint).
#
# Tests are no-op by default — set ENV['HEALTH_REGISTRY']=1 in a spec
# to opt into recording. This keeps assertions in unrelated specs
# stable; the buffer would otherwise leak state across examples.
module HealthRegistry
  CAPACITY           = 500
  DEGRADED_WINDOW    = 20    # consider only the last N observations
  DEGRADED_THRESHOLD = 0.5   # >=50% errors in that window → degraded
  DEGRADED_MIN       = 5     # need at least this many to call it

  Observation = Struct.new(:at, :feed_id, :status, :latency_ms, :note, keyword_init: true)

  MUTEX = Mutex.new

  module_function

  # Wraps a fetch (or any operation that returns a value with a .status
  # method matching FeedFetcher::Result). Records latency + status,
  # re-raises on exception. Returns the block's return value verbatim
  # so the wrap is invisible to callers.
  def measure(feed_id)
    return yield unless enabled?

    started = monotonic_now
    begin
      result = yield
      status = result.respond_to?(:status) ? result.status : :ok
      record(feed_id: feed_id, status: status, latency_ms: elapsed_ms(started))
      result
    rescue StandardError => e
      record(feed_id: feed_id, status: :error, latency_ms: elapsed_ms(started), note: e.class.name)
      raise
    end
  end

  def record(feed_id:, status:, latency_ms:, note: nil)
    return unless enabled?

    obs = Observation.new(
      at:         Time.now.utc.iso8601,
      feed_id:    feed_id,
      status:     status,
      latency_ms: latency_ms,
      note:       note
    )
    MUTEX.synchronize do
      buffer << obs
      buffer.shift while buffer.length > CAPACITY
    end
    obs
  end

  def observations
    MUTEX.synchronize { buffer.dup }
  end

  def observations_for(feed_id)
    observations.select { |o| o.feed_id == feed_id }
  end

  # Per-feed digest: { feed_id => {success:, errors:, total:, last:, avg_latency_ms:} }
  def per_feed_summary
    observations.group_by(&:feed_id).transform_values do |obs|
      total      = obs.length
      errors     = obs.count { |o| o.status == :error }
      successful = obs.reject { |o| o.status == :error }
      avg_latency = successful.empty? ? nil : (successful.sum(&:latency_ms) / successful.length.to_f).round
      {
        total:          total,
        success:        total - errors,
        errors:         errors,
        last:           obs.last,
        avg_latency_ms: avg_latency
      }
    end
  end

  # True when recent fetch behaviour looks broadly broken — used by the
  # dashboard banner. Conservative: a low sample count returns false.
  def degraded?
    obs = observations.last(DEGRADED_WINDOW)
    return false if obs.length < DEGRADED_MIN

    error_count = obs.count { |o| o.status == :error }
    (error_count.to_f / obs.length) >= DEGRADED_THRESHOLD
  end

  def reset!
    MUTEX.synchronize { @buffer = [] }
  end

  def enabled?
    ENV['RACK_ENV'] != 'test' || ENV['HEALTH_REGISTRY'] == '1'
  end

  class << self
    private

    def buffer
      @buffer ||= []
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def elapsed_ms(started)
      ((monotonic_now - started) * 1000).round
    end
  end
end
