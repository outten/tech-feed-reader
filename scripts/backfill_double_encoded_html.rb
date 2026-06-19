#!/usr/bin/env ruby
# STUFF #104 — one-time backfill: re-sanitize already-imported articles whose
# stored content_html contains double-encoded HTML tags (e.g. The Points Guy
# tables shipping `<td>&lt;strong&gt;...&lt;/strong&gt;</td>`, which rendered
# the literal text "<strong>" instead of bold).
#
# Sanitizer.sanitize_html now decodes those recognised inner tags (and
# re-prunes, so it stays XSS-safe), so re-running it over the stored
# content_html rewrites the affected rows. content_text is regenerated too so
# the FTS `tsv` (a generated column) re-indexes the cleaned text. Idempotent:
# only rows whose output actually changes are written.
#
# Usage:
#   DRY_RUN=1 VERBOSE=1 bundle exec ruby scripts/backfill_double_encoded_html.rb
#   bundle exec ruby scripts/backfill_double_encoded_html.rb        # writes
require_relative '../app/credentials'
require_relative '../app/database'
require_relative '../app/sanitizer'
require_relative '../app/logger'

Database.migrate!

DRY     = ENV['DRY_RUN'] == '1'
VERBOSE = ENV['VERBOSE'] == '1'

# Cheap pre-filter: any content_html that contains an encoded tag (`&lt;…&gt;`).
# The precise decode-or-no-op decision is made per row by re-sanitizing and
# comparing, so this just bounds the scan.
rows = Database.connection.execute(<<~SQL)
  SELECT id, uid, url, content_html
  FROM articles
  WHERE content_html LIKE '%&lt;%&gt;%'
SQL

scanned = rows.length
changed = 0

rows.each do |row|
  before = row['content_html'].to_s
  after  = Sanitizer.sanitize_html(before, base_url: row['url'])
  next if after == before

  changed += 1
  puts "  #{row['uid']}  #{row['url']}" if VERBOSE
  next if DRY

  Database.connection.execute(
    'UPDATE articles SET content_html = ?, content_text = ? WHERE id = ?',
    [after, Sanitizer.text_only(before), row['id']]
  )
end

AppLogger.info('backfill_double_encoded_html', scanned: scanned, changed: changed, dry_run: DRY)
puts ''
puts "Scanned:  #{scanned} (content_html containing encoded tags)"
puts "Changed:  #{changed}#{DRY ? ' (dry-run, not written)' : ''}"
