#!/usr/bin/env ruby
# STUFF #61 — manual entry point for the same logic the daily
# FixArticleLinksWorker cron job runs. Use this to force an
# immediate scrub from the command line.
#
# All work lives in app/article_link_scrubber.rb so the worker and
# the script share one code path.
#
# Usage:
#   make fix-article-links
#   DRY_RUN=1 VERBOSE=1 LIMIT=200 bundle exec ruby scripts/fix_article_links.rb

require_relative '../app/credentials'
require_relative '../app/database'
require_relative '../app/article_link_scrubber'
require_relative '../app/logger'

Database.migrate!

opts = {
  dry_run: ENV['DRY_RUN'] == '1',
  verbose: ENV['VERBOSE'] == '1',
  logger:  AppLogger
}
opts[:limit] = ENV['LIMIT'].to_i if ENV['LIMIT'].to_i.positive?

r = ArticleLinkScrubber.run!(**opts)

puts ''
puts "Scanned:   #{r[:scanned]} (content_scrubbed = FALSE)"
puts "Changed:   #{r[:changed]}#{opts[:dry_run] ? ' (dry-run, not written)' : ''}"
puts "Unchanged: #{r[:unchanged]} (already-absolute; flag bumped)"
puts "Skipped:   #{r[:skipped]} (no usable http(s) base url)"
puts "Empty:     #{r[:empty_marked]} (no content_html; flag bumped)"
puts "Remaining: #{r[:remaining]} unscrubbed"
