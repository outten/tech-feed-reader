require_relative 'version'

# OpenTelemetry boot path + in-memory recorder.
#
# What this gives you out of the box:
#   - Auto-instrumentation for Sinatra, Rack, Net::HTTP, Sidekiq, and
#     SQLite (via opentelemetry-instrumentation-all). Every HTTP request,
#     outbound fetch, job, and SQL query becomes a span automatically.
#   - Manual spans wrap FeedFetcher#fetch_feed and Summarizer::Claude#summarize
#     (search for `Tracing.in_span` in those files).
#   - An in-memory ring-buffer SpanProcessor (RecorderProcessor below)
#     keeps the last N finished spans so /admin/traces is useful even
#     without any external backend configured.
#   - When OTEL_EXPORTER_OTLP_ENDPOINT is set, a BatchSpanProcessor with
#     the OTLP exporter is also installed, so spans flow to your
#     collector (Jaeger, Tempo, Honeycomb, …) for retention + cross-
#     service correlation. The in-memory recorder runs alongside it.
#
# Test env always skips activation — RSpec runs hundreds of times and
# we don't want to start the SDK each time. Tracing tests stub
# Tracing.tracer / Tracing::Recorder directly.
#
# Service identity (resource attributes):
#   service.name     = OTEL_SERVICE_NAME or 'tech-feed-reader'
#   service.version  = AppVersion::GIT_SHA (computed at boot)
module Tracing
  ACTIVE = ENV['RACK_ENV'] != 'test'

  # In-memory ring buffer of finished spans. The /admin/traces page
  # reads from this; the buffer is process-local (web vs. worker each
  # have their own — same as Prometheus metrics).
  module Recorder
    DEFAULT_CAPACITY = 200
    MUTEX = Mutex.new
    @spans = []
    @capacity = (ENV['TRACING_RECORDER_CAPACITY'] || DEFAULT_CAPACITY).to_i

    module_function

    def capacity
      @capacity
    end

    def record(span_data)
      MUTEX.synchronize do
        @spans << span_data
        @spans.shift while @spans.length > @capacity
      end
    end

    # Newest first. Returns the underlying SpanData snapshots; the view
    # converts them to display rows.
    def spans
      MUTEX.synchronize { @spans.dup.reverse }
    end

    def clear!
      MUTEX.synchronize { @spans.clear }
    end

    def count
      MUTEX.synchronize { @spans.length }
    end
  end

  # Custom SpanProcessor: hands each finished span off to Recorder.
  # Spec for the SpanProcessor interface lives in
  # opentelemetry-sdk's tracing/span_processor.rb (on_start, on_finish,
  # force_flush, shutdown). We only care about on_finish; the rest are
  # no-ops. force_flush returns SUCCESS so a flush call doesn't stall.
  class RecorderProcessor
    def on_start(_span, _parent_context); end
    def on_finish(span)
      Recorder.record(span.to_span_data) if span.context.trace_flags.sampled?
    rescue StandardError
      # Never let a recorder bug crash the request that produced the span.
    end
    def force_flush(timeout: nil); 0; end
    def shutdown(timeout: nil);    0; end
  end

  if ACTIVE
    require 'opentelemetry/sdk'
    require 'opentelemetry/instrumentation/all'

    # Lazy-load the OTLP exporter only when it's wanted; the gem pulls
    # in google-protobuf which is heavy (~3 MB native ext). No need to
    # pay that on dev runs without an exporter configured.
    if !ENV['OTEL_EXPORTER_OTLP_ENDPOINT'].to_s.strip.empty?
      require 'opentelemetry/exporter/otlp'
      OTLP_ENABLED = true
    else
      OTLP_ENABLED = false
    end

    OpenTelemetry::SDK.configure do |c|
      c.service_name    = ENV.fetch('OTEL_SERVICE_NAME', 'tech-feed-reader')
      c.service_version = AppVersion::GIT_SHA
      c.use_all
      c.add_span_processor(RecorderProcessor.new)
      if OTLP_ENABLED
        c.add_span_processor(
          OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
            OpenTelemetry::Exporter::OTLP::Exporter.new
          )
        )
      end
    end
  else
    OTLP_ENABLED = false
    require 'opentelemetry'
  end

  module_function

  def enabled?
    ACTIVE
  end

  def otlp_enabled?
    OTLP_ENABLED
  end

  def endpoint
    ENV['OTEL_EXPORTER_OTLP_ENDPOINT'].to_s
  end

  def service_name
    ENV.fetch('OTEL_SERVICE_NAME', 'tech-feed-reader')
  end

  # Manual-span tracer for the few code paths that warrant explicit
  # instrumentation beyond the auto-instrumented Sinatra / Net::HTTP /
  # Sidekiq / SQLite spans. See FeedFetcher#fetch_feed and
  # Summarizer::Claude#summarize.
  def tracer
    OpenTelemetry.tracer_provider.tracer('tech-feed-reader', AppVersion::GIT_SHA)
  end

  # Sugar around tracer.in_span so call sites read clean. Yields the
  # span so callers can set status / record exceptions. Always usable
  # — when the SDK isn't active the API package's no-op tracer just
  # invokes the block.
  def in_span(name, attributes: {}, kind: nil, &block)
    opts = {}
    opts[:attributes] = attributes unless attributes.empty?
    opts[:kind]       = kind       if kind
    tracer.in_span(name, **opts, &block)
  end
end
