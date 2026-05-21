# Boot file for the Sidekiq worker process. Sidekiq starts with
#   bundle exec sidekiq -r ./app/sidekiq_boot.rb
# and this file requires the shared config + every worker class so jobs
# enqueued by the web process can be popped and run.
require 'yaml'
require_relative 'credentials'
require_relative 'database'
require_relative 'logger'
require_relative 'tracing'
require_relative 'sidekiq_config'
require_relative 'workers/feed_refresh_worker'
require_relative 'workers/sports_team_fetch_worker'
require_relative 'workers/refresh_all_feeds_worker'
require_relative 'workers/sports_sync_worker'

# Recurring jobs (hourly feed refresh, nightly sports sync). Loaded
# server-side only so the web process doesn't double-register the
# schedule. The yml is bundled into the container at /app/config/.
require 'sidekiq-cron'

Sidekiq.configure_server do |_config|
  schedule_path = File.expand_path('../config/sidekiq_cron.yml', __dir__)
  if File.exist?(schedule_path)
    schedule = YAML.safe_load(File.read(schedule_path), aliases: true) || {}
    Sidekiq::Cron::Job.load_from_hash(schedule)
    AppLogger.info('sidekiq_cron_loaded', jobs: schedule.keys)
  else
    AppLogger.warn('sidekiq_cron_schedule_missing', path: schedule_path)
  end
end
