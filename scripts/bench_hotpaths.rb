#!/usr/bin/env ruby
# Micro-benchmark for the performance hot paths (see the perf work).
# Times the queries that drive the home page + /articles against the
# DATABASE_URL you point it at, so we get an apples-to-apples local
# before/after delta per phase.
#
# Usage:
#   DATABASE_URL=postgres://localhost/tfr_dev bundle exec ruby scripts/bench_hotpaths.rb [user_id] [runs]
#
# Read-only — runs SELECTs only.

require_relative '../app/credentials'
require_relative '../app/database'
require_relative '../app/articles_store'
require_relative '../app/read_state_store'
require_relative '../app/feed_feedback_store'
require_relative '../app/recommendation'
require_relative '../app/recommendation/for_you'

USER_ID = (ARGV[0] || 1).to_i
RUNS    = (ARGV[1] || 5).to_i

def time_ms
  t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  yield
  ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t) * 1000).round(1)
end

def bench(label, runs)
  yield # warm-up (prime cache) — not counted
  samples = Array.new(runs) { time_ms { yield } }
  sorted  = samples.sort
  median  = sorted[sorted.length / 2]
  printf("  %-32s median=%7.1fms  min=%7.1fms  max=%7.1fms\n", label, median, sorted.first, sorted.last)
end

puts "bench_hotpaths — user_id=#{USER_ID}, #{RUNS} runs (after 1 warm-up), DB=#{ENV['DATABASE_URL']}"
puts

bench('ReadStateStore.unread_count', RUNS) { ReadStateStore.unread_count(USER_ID) }
bench('ArticlesStore.recent(limit:50)', RUNS) { ArticlesStore.recent(USER_ID, limit: 50) }
bench('ForYou.score_window(limit:200)', RUNS) do
  Recommendation::ForYou.score_window(USER_ID, state: :all, limit: 200, offset: 0)
end

puts
puts "done."
