#!/usr/bin/env ruby
# Standalone retention sweep — `make prune`. Same logic as the post-
# refresh hook in scripts/refresh_feeds.rb, exposed separately so it
# can run from cron / launchd / a one-off shell, or be folded into
# any other script.
#
# Env knobs:
#   RETENTION_DAYS      default 7 (Pruner::DEFAULT_RETENTION_DAYS)
#   PRUNE_KEEP_UNREAD   set to "1" to also preserve unread articles
#
# Always preserved: bookmarked articles (regardless of age).
# Cascades take care of read_state, summaries, article_tags, and the
# articles_fts index.
require_relative '../app/database'
require_relative '../app/pruner'

Database.migrate!

retention_days = Integer(ENV.fetch('RETENTION_DAYS', Pruner::DEFAULT_RETENTION_DAYS), 10)
keep_unread    = ENV['PRUNE_KEEP_UNREAD'] == '1'

result = Pruner.prune_old(retention_days: retention_days, keep_unread: keep_unread)

puts "Retention: #{retention_days} day#{'s' unless retention_days == 1}"
puts "Cutoff:    #{result.cutoff}"
puts "Deleted:   #{result.deleted}"
puts "Kept (bookmarked, past cutoff): #{result.kept_bookmarked}"
puts "Kept (unread, past cutoff):    #{result.kept_unread}" if keep_unread
