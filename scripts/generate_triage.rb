#!/usr/bin/env ruby
# Cron entry point — generates AI-assisted triages and persists
# each via TriageStore. Mirrors scripts/generate_digest.rb.
#
# Usage:
#   make triage
#   bundle exec ruby scripts/generate_triage.rb
#
# Phase S10 follow-up — runs three triages per invocation:
#   1. Cross-topic (legacy default, NULL topic)
#   2. technology-only
#   3. sports-only
#
# Each costs ~$0.02–0.04 on Claude Sonnet 4.6, so the daily cron
# spend is ~$0.10/day. Browse all stored runs at /triage; topic
# chips on that page filter the historical list.
#
# Exit codes:
#   0 — every run was :ok / :empty / :parse_error (we still persisted
#       parse_error rows so the user can see the raw output).
#   2 — at least one run came back :unavailable (no API key).
#   3 — at least one run came back :error (real failure).
#
# Cron alerts fire on non-zero exit.
require_relative '../app/credentials'
require_relative '../app/database'
require_relative '../app/triage/claude'
require_relative '../app/triage_store'
require_relative '../app/logger'

Database.migrate!

# nil = cross-topic legacy run; the rest scope unread + corpus to
# one feed.topic. Order matters only for log readability.
TRIAGE_TOPICS = [nil, 'technology', 'sports'].freeze

failures = []
TRIAGE_TOPICS.each do |topic|
  scope = topic || 'all'
  result = Triage::Claude.run(topic: topic)

  case result.status
  when :unavailable
    warn "Triage::Claude unavailable (topic=#{scope}) — set ANTHROPIC_API_KEY in .credentials."
    failures << :unavailable
    next
  when :error
    warn "Triage::Claude failed (topic=#{scope}): #{result.error}"
    TriageStore.create(result)
    failures << :error
    next
  end

  id = TriageStore.create(result)
  puts "Triage stored id=#{id} topic=#{scope} status=#{result.status} " \
       "must_read=#{result.must_read.length} optional=#{result.optional.length} " \
       "skip=#{result.skip.length}"
end

exit 2 if failures.include?(:unavailable)
exit 3 if failures.include?(:error)
exit 0
