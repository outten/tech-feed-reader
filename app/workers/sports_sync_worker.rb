require 'sidekiq'
require_relative '../sports_sync'
require_relative '../logger'

# Nightly Sidekiq-cron job: pull schedules + standings for every
# followed team, then refresh ATP/WTA tennis rankings. Wraps the
# shared SportsSync.run! module so the worker and the manual
# `make sync-sports` entry point share one code path.
#
# Idempotent — each upsert keys on (source_provider, external_id),
# so retries and overlapping runs never duplicate rows.
class SportsSyncWorker
  include Sidekiq::Worker

  # ESPN can be flaky; keep retries small (don't pile up 25 attempts
  # while the next nightly run is already coming).
  sidekiq_options queue: :default, retry: 2

  def perform
    result = SportsSync.run!(logger: AppLogger)
    AppLogger.info('sports_sync_complete', **result)
  end
end
