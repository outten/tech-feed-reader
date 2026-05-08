#!/usr/bin/env ruby
# Generate a digest snapshot and persist it to the digests table. The
# /digests page lists rows newest-first; /digests/:id renders the
# stored html_body inline.
#
# Idempotent in the boring sense: every run inserts a new row, so
# wiring this to cron once a day gives you one row per day. Running
# it twice gives you two rows; that's by design (no de-dup) so a
# manual `make digest` for testing doesn't get lost.
#
# Wire to cron / launchd to fire daily, e.g.:
#
#   # crontab -e — fire every morning at 7am local
#   0 7 * * *  cd /path/to/tech-feed-reader && bundle exec ruby scripts/generate_digest.rb >> tmp/logs/digest.log 2>&1
#
# Env (optional):
#   DIGEST_WINDOW_HOURS  default 24
#   DIGEST_LIMIT         default 25
require_relative '../app/credentials'
require_relative '../app/database'
require_relative '../app/digests'
require_relative '../app/digest_store'
require_relative '../app/logger'

Database.migrate!

window = Integer(ENV.fetch('DIGEST_WINDOW_HOURS', '24'), 10)
limit  = Integer(ENV.fetch('DIGEST_LIMIT',        '25'), 10)

id, result = Digests.generate_and_store!(window_hours: window, limit: limit)

AppLogger.info('digest_stored',
               id: id,
               count: result.count,
               window_hours: window,
               subject: result.subject)
puts "Stored digest ##{id}: #{result.count} unread article(s) in last #{window}h"
puts "Browse at /digests"
