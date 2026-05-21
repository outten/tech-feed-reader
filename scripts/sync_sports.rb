#!/usr/bin/env ruby
# Manual entry point for the same logic the nightly SportsSyncWorker
# cron job runs. Use this to force an immediate sync from the command
# line (e.g. `make sync-sports` after adding a new league).
#
# All work lives in app/sports_sync.rb so the worker and the script
# share one code path.
#
# Usage:
#   make sync-sports
#   bundle exec ruby scripts/sync_sports.rb

require_relative '../app/credentials'
require_relative '../app/database'
require_relative '../app/sports_sync'
require_relative '../app/logger'

Database.migrate!

result = SportsSync.run!(logger: AppLogger)

puts
puts "Done. matches_upserted=#{result[:matches_upserted]} matches_total=#{result[:matches_total]} " \
     "standings_total=#{result[:standings_total]} tennis_total=#{result[:tennis_total]}"
