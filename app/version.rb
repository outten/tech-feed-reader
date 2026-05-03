require 'time'

# Lightweight version + boot-time capture for /health and /admin.
#
# Read once at boot:
#   - GIT_SHA: env override (set by CI / Docker build), else `git rev-parse`
#               of the working tree, else 'unknown'.
#   - STARTED_AT: process boot timestamp in UTC. /health computes uptime
#                 against this every request — it's a Time, not a string,
#                 so the math is cheap.
#
# The git lookup shells out at require time. Failures fall through to
# 'unknown' so a deploy without a .git directory still boots cleanly.
module AppVersion
  STARTED_AT = Time.now.utc

  GIT_SHA = (ENV['GIT_SHA'] || ENV['SOURCE_COMMIT'] || begin
    out = `git rev-parse --short=12 HEAD 2>/dev/null`.strip
    out.empty? ? 'unknown' : out
  rescue StandardError
    'unknown'
  end).freeze

  module_function

  def uptime_seconds
    (Time.now.utc - STARTED_AT).to_i
  end
end
