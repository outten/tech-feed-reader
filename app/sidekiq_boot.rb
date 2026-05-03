# Boot file for the Sidekiq worker process. Sidekiq starts with
#   bundle exec sidekiq -r ./app/sidekiq_boot.rb
# and this file requires the shared config + every worker class so jobs
# enqueued by the web process can be popped and run.
require 'dotenv/load'
require_relative 'database'
require_relative 'logger'
require_relative 'tracing'
require_relative 'sidekiq_config'
require_relative 'workers/feed_refresh_worker'
