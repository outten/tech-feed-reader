require 'time'

# Lightweight version + boot-time capture for /health, footer, /admin.
#
# Read once at boot:
#   - SEMVER:  contents of /VERSION (the project root file). Bumped by
#              `make deploy-major / -minor / -patch` via
#              scripts/bump_version.rb. The canonical "what release am
#              I looking at" identifier shown in the footer and the
#              Docker image's OCI label.
#   - GIT_SHA: env override (set by CI / Docker build), else `git rev-parse`
#               of the working tree, else 'unknown'. Finer-grained than
#               SEMVER — distinguishes commits between version bumps.
#   - STARTED_AT: process boot timestamp in UTC. /health computes uptime
#                 against this every request — it's a Time, not a string,
#                 so the math is cheap.
#
# Both lookups have safe fallbacks ('unknown') so the app boots cleanly
# in any environment (missing VERSION file in a slim test image, no .git
# directory in a deploy artifact, etc).
module AppVersion
  STARTED_AT = Time.now.utc

  VERSION_FILE = File.expand_path('../../VERSION', __FILE__)

  SEMVER = (ENV['APP_VERSION'] || begin
    File.read(VERSION_FILE).strip
  rescue StandardError
    'unknown'
  end).freeze

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
