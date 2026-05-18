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

  # Resolution order at boot:
  #   1. ENV['APP_VERSION'] if set AND non-empty (the Docker build-arg path).
  #   2. /VERSION file (always shipped in the image via COPY).
  #   3. Literal 'unknown' (only if both above fail).
  #
  # The empty-string check is load-bearing: Ruby's `||` treats "" as
  # truthy, so `ENV['APP_VERSION'] || File.read(...)` happily returns ""
  # on any container where APP_VERSION is set-but-empty — which is
  # exactly what Docker's `ENV X=${X}` produces when no build-arg is in
  # scope at that point in the Dockerfile (the bug we tripped over on
  # the first DOCR-published image, where the runtime stage lacked an
  # ARG re-declare).
  #
  # Extracted as a class method so the spec can exercise the
  # empty-ENV / present-ENV / missing-file branches; the SEMVER
  # constant just freezes one invocation at module load.
  def self.resolve_semver
    env = ENV['APP_VERSION'].to_s.strip
    return env unless env.empty?
    File.read(VERSION_FILE).strip
  rescue StandardError
    'unknown'
  end

  SEMVER = resolve_semver.freeze

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
