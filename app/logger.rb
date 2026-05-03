require 'logger'
require 'json'

# Single-process JSON logger writing one event per line to STDOUT.
# Each log line is a self-contained JSON object so a downstream
# consumer (jq, lnav, a future log shipper) can index any field.
#
# Usage:
#   AppLogger.info('feed_fetch', feed_id: 1, status: :ok, latency_ms: 142)
#   AppLogger.warn('llm_unavailable', reason: 'no API key')
#   AppLogger.error('http_error', class: e.class.name, message: e.message)
#
# Levels follow stdlib Logger: debug / info / warn / error / fatal.
# Tweak via ENV['LOG_LEVEL']; default is 'info' in dev / production
# and 'fatal' in test (so RSpec output stays clean).
module AppLogger
  module_function

  def info(event, **context);  emit(::Logger::INFO,  event, context); end
  def warn(event, **context);  emit(::Logger::WARN,  event, context); end
  def error(event, **context); emit(::Logger::ERROR, event, context); end
  def debug(event, **context); emit(::Logger::DEBUG, event, context); end

  # Reset the cached logger — used by tests to capture output to a
  # different IO without polluting global state.
  def reset!(io: nil)
    @instance = io ? build(io) : nil
  end

  def instance
    @instance ||= build($stdout)
  end

  class << self
    private

    def emit(level, event, context)
      return unless instance.level <= level
      instance.add(level, { event: event.to_s, **context })
    end

    def build(io)
      logger = ::Logger.new(io)
      logger.level     = level_from_env
      logger.formatter = JsonFormatter.new
      logger
    end

    def level_from_env
      raw = ENV['LOG_LEVEL'] || (ENV['RACK_ENV'] == 'test' ? 'fatal' : 'info')
      case raw.to_s.downcase
      when 'debug' then ::Logger::DEBUG
      when 'info'  then ::Logger::INFO
      when 'warn'  then ::Logger::WARN
      when 'error' then ::Logger::ERROR
      when 'fatal' then ::Logger::FATAL
      else              ::Logger::INFO
      end
    end
  end

  # Renders each log call as `{"ts":"...","level":"info","event":"...",...}\n`.
  # Hash payloads are merged in directly; string payloads land in a
  # `message` field for backward compat with raw `Logger#info("text")`.
  class JsonFormatter
    def call(severity, time, _progname, msg)
      base = { ts: time.utc.strftime('%Y-%m-%dT%H:%M:%S.%3NZ'), level: severity.downcase }
      payload = msg.is_a?(Hash) ? msg : { message: msg.to_s }
      JSON.generate(base.merge(payload)) + "\n"
    rescue StandardError => e
      # Never let a logger formatter exception crash the app — fall
      # back to a minimal record so the operator still sees the
      # original event signal.
      JSON.generate(ts: time.utc.iso8601, level: severity.downcase, event: 'logger_format_error', error: e.class.name) + "\n"
    end
  end
end
