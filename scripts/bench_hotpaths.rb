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

# ---- Cold article-load breakdown (change: speed-up-article-load) -----------
# The /article/:uid page pays ForYou.next_after on a cold cache, which runs
# compute_ranking (no internal cache — every call is a full cold compute).
# Break it into its SQL parts (corpus queries + candidate fetch) and its CPU
# part (the tokenize-and-score loop) so we know whether the cost is IO- or
# CPU-bound before optimizing.
puts
puts "cold article-load breakdown (ForYou.next_after path):"
require_relative '../app/cache'
NOW = Time.now.utc
F   = Recommendation::ForYou

bench('  positive_corpus (SQL)', RUNS)           { F.positive_corpus(USER_ID) }
bench('  negative_corpus (SQL)', RUNS)           { F.negative_corpus(USER_ID) }
bench('  corpus_terms pos (SQL+tokenize)', RUNS) { F.corpus_terms(USER_ID, positive: true) }
bench('  candidate fetch recent(500,unread) (SQL)', RUNS) do
  ArticlesStore.recent(USER_ID, limit: 500, state: :unread)
end

# Isolate the CPU scoring loop: precompute the inputs once, then time only
# the map/score/sort over the 500-candidate window.
pos_terms = F.corpus_terms(USER_ID, positive: true)
neg_terms = F.corpus_terms(USER_ID, positive: false)
cands     = ArticlesStore.recent(USER_ID, limit: 500, state: :unread)
fweights  = FeedFeedbackStore.weights_by_feed_id(USER_ID, cands.map { |a| a['feed_id'] })
bench("  score loop only (CPU, #{cands.length} cands)", RUNS) do
  cands.map { |a|
    [a['id'], F.score_article(a, pos_terms: pos_terms, neg_terms: neg_terms,
                              feed_weight: fweights[a['feed_id']] || 1.0, now: NOW)]
  }.sort_by { |_id, s| -s }
end

bench('ForYou.compute_ranking COLD (full)', RUNS) do
  F.compute_ranking(USER_ID, state: :unread, kind: :all, topic: nil, now: NOW)
end

cold_art = ArticlesStore.recent(USER_ID, limit: 1, state: :unread).first
if cold_art
  rank_key = "foryou:v1:#{USER_ID}:unread:all:-"
  bench('ForYou.next_after COLD (cache-busted)', RUNS) do
    Cache.delete(rank_key)
    F.next_after(USER_ID, cold_art, now: NOW)
  end
end

# Related panel (change: async-related-articles). Bench on a CONTENT-FUL
# article (non-empty keywords) — a body-less one short-circuits to [] and
# hides the real cost. `compute_related` bypasses the cache so each run is a
# true cold compute of the recency-bounded ts_rank query.
require_relative '../app/recommendation'
real_art = ArticlesStore.recent(USER_ID, limit: 200, state: :all)
                        .find { |a| !Recommendation.top_keywords(a['content_text'].to_s).empty? }
if real_art
  kw = Recommendation.top_keywords(real_art['content_text'].to_s)
  bench('Recommendation.compute_related (content-ful)', RUNS) do
    Recommendation.compute_related(USER_ID, real_art['id'], kw, 5)
  end
end

puts
puts "done."
