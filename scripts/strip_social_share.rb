#!/usr/bin/env ruby
# One-shot backfill: re-sanitize existing articles to strip social sharing
# buttons that were ingested before SocialShareScrubber was added.
#
# Usage:
#   bundle exec ruby scripts/strip_social_share.rb
#   bundle exec ruby scripts/strip_social_share.rb --dry-run
#   bundle exec ruby scripts/strip_social_share.rb --limit 500
#
# Unlike fix_article_links.rb, this touches ALL articles with content_html
# (not just content_scrubbed = FALSE) because the social-share pass is new
# and independent of the link-absolutization flag.
require_relative '../app/database'
require_relative '../app/sanitizer'

dry_run = ARGV.include?('--dry-run')
limit   = (i = ARGV.index('--limit')) ? Integer(ARGV[i + 1]) : nil

puts dry_run ? '[dry-run] no rows will be written' : '[live] rows will be updated'
puts

sql = <<~SQL
  SELECT id, uid, url, content_html
  FROM articles
  WHERE content_html IS NOT NULL AND content_html <> ''
  ORDER BY id
  #{limit ? "LIMIT #{Integer(limit)}" : ''}
SQL

scanned = changed = unchanged = 0

Database.connection.execute(sql).each do |row|
  scanned += 1

  before = row['content_html'].to_s
  url    = row['url'].to_s
  after  = Sanitizer.sanitize_html(before, base_url: url.match?(%r{\Ahttps?://}i) ? url : nil)

  if after == before
    unchanged += 1
    next
  end

  changed += 1
  puts "  changed uid=#{row['uid']} url=#{url[0, 80]}"

  next if dry_run

  Database.connection.execute(
    'UPDATE articles SET content_html = $1 WHERE id = $2',
    [after, row['id']]
  )
end

puts
puts "scanned=#{scanned}  changed=#{changed}  unchanged=#{unchanged}"
puts dry_run ? '[dry-run] no rows written' : 'done'
