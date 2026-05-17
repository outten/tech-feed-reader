#!/usr/bin/env ruby
# STUFF #33A. Semver bumper for /VERSION.
#
# Usage:
#   ruby scripts/bump_version.rb major    # 0.9.0 → 1.0.0
#   ruby scripts/bump_version.rb minor    # 0.9.0 → 0.10.0
#   ruby scripts/bump_version.rb patch    # 0.9.0 → 0.9.1
#
# Reads /VERSION, parses semver, writes the bump back. Prints the new
# value to stdout (and only that, so callers can capture it). Errors go
# to stderr.
#
# Driven by `make deploy-major / -minor / -patch`, which run tests
# first, then bump, then tag + push. The script itself is git-agnostic
# — it only touches VERSION on disk.

require 'optparse'

module BumpVersion
  module_function

  VERSION_FILE = File.expand_path('../../VERSION', __FILE__)
  KINDS        = %w[major minor patch].freeze
  SEMVER_RX    = /\A(\d+)\.(\d+)\.(\d+)\z/.freeze

  def run(argv)
    kind = argv.first
    abort_with("missing argument: expected one of #{KINDS.join(' / ')}") unless kind
    abort_with("unknown kind '#{kind}': expected one of #{KINDS.join(' / ')}") unless KINDS.include?(kind)

    current = read_version
    next_version = bump(current, kind)
    write_version(next_version)
    puts next_version
    next_version
  end

  def read_version
    raw = File.read(VERSION_FILE).strip
    abort_with("VERSION file does not match semver (got #{raw.inspect})") unless raw.match?(SEMVER_RX)
    raw
  rescue Errno::ENOENT
    abort_with("VERSION file not found at #{VERSION_FILE}")
  end

  # Pure: takes the current string, returns the next one. Tested in spec.
  def bump(current, kind)
    m = current.match(SEMVER_RX) or raise ArgumentError, "not semver: #{current.inspect}"
    major, minor, patch = m.captures.map(&:to_i)
    case kind
    when 'major' then "#{major + 1}.0.0"
    when 'minor' then "#{major}.#{minor + 1}.0"
    when 'patch' then "#{major}.#{minor}.#{patch + 1}"
    else raise ArgumentError, "unknown kind: #{kind.inspect}"
    end
  end

  def write_version(value)
    File.write(VERSION_FILE, "#{value}\n")
  end

  def abort_with(msg)
    warn "bump_version: #{msg}"
    exit 1
  end
end

BumpVersion.run(ARGV) if $PROGRAM_NAME == __FILE__
