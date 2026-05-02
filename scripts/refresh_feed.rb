#!/usr/bin/env ruby
# One-shot poll of a single feed by id or URL. Mirrors the per-row
# Refresh button on /feeds — same Scheduler.refresh_one entry point,
# same HealthRegistry observation lands in /admin/health.
#
# Usage:
#   make refresh-feed FEED=3
#   make refresh-feed FEED=https://news.ycombinator.com/rss
require_relative '../app/database'
require_relative '../app/feeds_store'
require_relative '../app/scheduler'

Database.migrate!

target = ARGV.first
if target.nil? || target.empty?
  abort "Usage: scripts/refresh_feed.rb <feed-id-or-url>"
end

feed = if target.match?(/\A\d+\z/)
         FeedsStore.find(target.to_i)
       else
         FeedsStore.find_by_url(target)
       end

abort "No feed matches: #{target.inspect}" unless feed

label = feed['title'] || feed['url']
puts "Fetching #{label}..."

result, imported = Scheduler.refresh_one(feed)
puts "  status:   #{result.status}"
puts "  imported: #{imported}"
puts "  error:    #{result.error}" if result.error

exit(result.status == :error ? 1 : 0)
