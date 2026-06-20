require 'sidekiq'
require 'sidekiq/api'
require 'time'
require_relative '../database'
require_relative '../notifier'
require_relative '../cache'
require_relative '../logger'

# Periodic liveness + degradation check (pre-launch ops alerting).
# Runs every few minutes via sidekiq-cron and pushes an ntfy alert when a
# check fails. Because it runs INSIDE Sidekiq it cannot detect a Sidekiq /
# Redis outage (the job simply wouldn't run) — that blind spot, and how to
# close it with an external dead-man's switch, is documented in
# docs/alerting.md. What it DOES catch while the worker is alive:
#   - Postgres unreachable
#   - the feed-import pipeline stalled (no article fetched in FRESH_HOURS)
#   - the Sidekiq dead set growing (jobs exhausting all retries)
#
# Alerts fire only on a state TRANSITION (ok→problem, problem→ok), tracked
# in Redis, so a sustained fault pushes once — not every tick.
class HealthAlertWorker
  include Sidekiq::Worker
  sidekiq_options queue: :default, retry: 1

  STATE_KEY   = 'health:state'
  FRESH_HOURS = (ENV['HEALTH_FRESH_HOURS'] || '6').to_f
  DEAD_MAX    = (ENV['HEALTH_DEAD_MAX'] || '25').to_i

  def perform
    transition!(collect_problems)
  rescue StandardError => e
    # The checker failing is itself worth knowing about, but must not crash.
    AppLogger.error('health_alert_worker_error', message: e.message)
  end

  # Returns an array of human-readable problem strings ([] when healthy).
  def collect_problems
    problems = []

    begin
      Database.connection.execute('SELECT 1')
    rescue StandardError => e
      problems << "Postgres unreachable (#{e.class}: #{e.message})"
    end

    age = newest_fetch_age_hours
    if age && age > FRESH_HOURS
      problems << "Feed pipeline stalled — newest article fetched #{age.round(1)}h ago (> #{FRESH_HOURS}h)"
    end

    dead = dead_set_size
    if dead && dead > DEAD_MAX
      problems << "Sidekiq dead set at #{dead} jobs (> #{DEAD_MAX}) — jobs are exhausting retries"
    end

    problems
  end

  private

  def transition!(problems)
    now_bad = !problems.empty?
    was_bad = current_state == 'bad'

    if now_bad && !was_bad
      Notifier.push(
        title:    'Feeder health: PROBLEM',
        body:     problems.join("\n"),
        tags:     %w[rotating_light],
        priority: 'high'
      )
    elsif !now_bad && was_bad
      Notifier.push(
        title:    'Feeder health: recovered',
        body:     'All checks passing again.',
        tags:     %w[white_check_mark],
        priority: 'default'
      )
    end

    store_state(now_bad ? 'bad' : 'ok')
    AppLogger.info('health_alert_check', status: now_bad ? 'bad' : 'ok', problems: problems)
  end

  # MAX(fetched_at) is the import-pipeline heartbeat — it's stamped when an
  # article is imported. (published_at is unreliable: some feeds backdate or
  # post future timestamps.) fetched_at is text ISO8601, so parse in Ruby.
  def newest_fetch_age_hours
    row = Database.connection.execute('SELECT MAX(fetched_at) AS m FROM articles').first
    raw = row && row['m']
    return nil if raw.nil? || raw.to_s.empty?
    (Time.now.utc - Time.parse(raw.to_s)) / 3600.0
  rescue StandardError
    nil
  end

  def dead_set_size
    Sidekiq::DeadSet.new.size
  rescue StandardError
    nil
  end

  def current_state
    Cache.client.call('GET', STATE_KEY)
  rescue StandardError
    nil
  end

  def store_state(state)
    Cache.client.call('SET', STATE_KEY, state, 'EX', 86_400)
  rescue StandardError
    nil
  end
end
