#!/usr/bin/env ruby
# Cron entry point — generates an AI-assisted triage and persists
# it via TriageStore. Mirrors scripts/generate_digest.rb.
#
# Usage:
#   make triage
#   bundle exec ruby scripts/generate_triage.rb
#
# Pair with launchd / cron (daily, after the morning refresh) to
# get a fresh "must read / optional / skip" classification waiting
# at /triage/:id every morning. Browse all stored runs at /triage.
#
# Exits 0 on :ok / :empty / :parse_error (we still recorded the
# run); exits non-zero on :unavailable / :error so cron alerts
# fire on real misconfiguration.

require_relative '../app/credentials'
require_relative '../app/database'
require_relative '../app/triage/claude'
require_relative '../app/triage_store'
require_relative '../app/logger'

Database.migrate!

result = Triage::Claude.run

case result.status
when :unavailable
  warn 'Triage::Claude unavailable — set ANTHROPIC_API_KEY in .credentials.'
  exit 2
when :error
  warn "Triage::Claude failed: #{result.error}"
  # Persist the error row so the operator can see it at /triage.
  TriageStore.create(result)
  exit 3
end

id = TriageStore.create(result)
puts "Triage run stored as id=#{id}, status=#{result.status}, " \
     "must_read=#{result.must_read.length}, " \
     "optional=#{result.optional.length}, " \
     "skip=#{result.skip.length}"
exit 0
