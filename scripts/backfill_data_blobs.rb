#!/usr/bin/env ruby
# One-time backfill: re-sanitize already-imported articles whose stored
# content_html contains serialized component / community data blobs that leak
# into the body as visible JSON text (HuggingFace discussion threads, Condé
# Nast commerce widgets).
#
# Sanitizer.sanitize_html now strips those text nodes (see strip_data_blobs!),
# so re-running it over the stored content_html rewrites the affected rows.
# content_text is regenerated too so the FTS `tsv` (a generated column)
# re-indexes the cleaned text. Idempotent: only rows whose output actually
# changes are written.
#
# Usage:
#   DRY_RUN=1 VERBOSE=1 bundle exec ruby scripts/backfill_data_blobs.rb
#   bundle exec ruby scripts/backfill_data_blobs.rb        # writes
require_relative '../app/credentials'
require_relative '../app/database'
require_relative '../app/sanitizer'
require_relative '../app/logger'

Database.migrate!

DRY     = ENV['DRY_RUN'] == '1'
VERBOSE = ENV['VERBOSE'] == '1'

# Cheap pre-filter for the serialization keys strip_data_blobs! looks for.
# The precise strip-or-no-op decision is made per row by re-sanitizing and
# comparing, so this just bounds the scan.
rows = Database.connection.execute(<<~SQL)
  SELECT id, uid, url, content_html
  FROM articles
  WHERE content_html LIKE '%"updatedAt":%'
     OR content_html LIKE '%dangerousDek%'
     OR content_html LIKE '%"componentName":%'
SQL

scanned = rows.length
changed = 0
saved   = 0

rows.each do |row|
  before = row['content_html'].to_s
  after  = Sanitizer.sanitize_html(before, base_url: row['url'])
  next if after == before

  changed += 1
  saved   += (before.length - after.length)
  puts "  #{row['uid']}  -#{before.length - after.length}c  #{row['url']}" if VERBOSE
  next if DRY

  Database.connection.execute(
    'UPDATE articles SET content_html = ?, content_text = ? WHERE id = ?',
    [after, Sanitizer.text_only(before), row['id']]
  )
end

AppLogger.info('backfill_data_blobs', scanned: scanned, changed: changed, bytes_saved: saved, dry_run: DRY)
puts ''
puts "Scanned:  #{scanned} (content_html with serialization keys)"
puts "Changed:  #{changed}#{DRY ? ' (dry-run, not written)' : ''}"
puts "Saved:    #{saved} chars of blob text"
