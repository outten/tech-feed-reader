#!/usr/bin/env ruby
# Long-running poller. On each tick, picks every feed whose
# fetch_interval_seconds has elapsed since last_fetched_at and refreshes
# it. Sleeps SCHEDULER_TICK seconds between scans (default 60).
#
# Designed to run under launchd / systemd / tmux; SIGINT and SIGTERM
# stop the loop cleanly between feeds. State lives in SQLite — kill
# and restart the process safely; the next tick picks up from
# last_fetched_at.
#
# Usage:
#   make scheduler
#   SCHEDULER_TICK=30 make scheduler
require 'time'
require_relative '../app/database'
require_relative '../app/feeds_store'
require_relative '../app/scheduler'
require_relative '../app/health_registry'

Database.migrate!

TICK_SECONDS = (ENV['SCHEDULER_TICK'] || '60').to_i

stopping = false
%w[INT TERM].each do |sig|
  trap(sig) do
    stopping = true
    warn "\n[scheduler] received SIG#{sig}; will stop after the current tick"
  end
end

puts "[scheduler] started (tick=#{TICK_SECONDS}s, health_registry=#{HealthRegistry.enabled?})"

until stopping
  now   = Time.now.utc
  feeds = FeedsStore.all
  due   = Scheduler.due_feeds(feeds, now: now)

  if due.empty?
    puts "[#{now.iso8601}] tick: 0 due / #{feeds.length} feeds"
  else
    puts "[#{now.iso8601}] tick: #{due.length} due / #{feeds.length} feeds"
    due.each do |feed|
      break if stopping
      label = feed['title'] || feed['url']
      result, imported = Scheduler.refresh_one(feed)
      puts "  #{label}: status=#{result.status} imported=#{imported}"
    end
  end

  break if stopping
  sleep TICK_SECONDS
end

puts '[scheduler] stopped'
