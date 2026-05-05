#!/usr/bin/env ruby
# One-shot poll of every feed in FeedsStore. Mirrors the "Refresh all"
# button on /feeds. Synchronous and sequential; for the default 5-feed
# starter set this is fine. The long-running scripts/scheduler.rb is
# the right tool once polling cadence matters.
#
# After every refresh, sweeps articles older than RETENTION_DAYS
# (default 7). Bookmarked articles are always preserved; set
# PRUNE_KEEP_UNREAD=1 to also keep unread items past the window.
# PRUNE_ON_REFRESH=0 disables the sweep for this run.
#
# Usage:
#   make refresh-feeds
require_relative '../app/database'
require_relative '../app/feeds_store'
require_relative '../app/scheduler'
require_relative '../app/pruner'

Database.migrate!

feeds = FeedsStore.all
if feeds.empty?
  puts 'No feeds subscribed. Add one via /feeds or `make seed-feeds`.'
  exit 0
end

summary = { ok: 0, not_modified: 0, error: 0, imported: 0 }
feeds.each do |feed|
  label = feed['title'] || feed['url']
  print "Fetching #{label}... "

  result, imported = Scheduler.refresh_one(feed)
  summary[result.status] = (summary[result.status] || 0) + 1
  summary[:imported]    += imported

  case result.status
  when :ok           then puts "ok (+#{imported})"
  when :not_modified then puts '304 not_modified'
  when :error        then puts "error (#{result.error})"
  end
end

puts ''
puts "Summary: ok=#{summary[:ok]}  not_modified=#{summary[:not_modified]}  " \
     "error=#{summary[:error]}  imported=#{summary[:imported]}"

if ENV['PRUNE_ON_REFRESH'] != '0'
  retention_days = Integer(ENV.fetch('RETENTION_DAYS', Pruner::DEFAULT_RETENTION_DAYS), 10)
  keep_unread    = ENV['PRUNE_KEEP_UNREAD'] == '1'
  result = Pruner.prune_old(retention_days: retention_days, keep_unread: keep_unread)
  puts "Pruned: #{result.deleted} article#{'s' unless result.deleted == 1} older than #{retention_days}d (cutoff #{result.cutoff})  " \
       "kept_bookmarked=#{result.kept_bookmarked}#{keep_unread ? "  kept_unread=#{result.kept_unread}" : ''}"
end

exit(summary[:error].positive? && summary[:ok].zero? ? 1 : 0)
