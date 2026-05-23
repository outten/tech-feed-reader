require_relative 'database'
require_relative 'sanitizer'

# STUFF #61 — re-sanitize article content_html with each article's
# own URL as the absolute-link base, rewriting relative `<a href>`
# and `<img src>` to absolute URLs.
#
# Two entry points share this module so the manual + cron paths can't
# drift apart:
#   - scripts/fix_article_links.rb       (operator one-shot)
#   - app/workers/fix_article_links_worker.rb (daily Sidekiq-cron job)
#
# The maintenance pass is idempotent (filters WHERE
# content_scrubbed = FALSE and bumps the flag after each row), so a
# daily cron run in steady state should touch only the handful of
# articles that came in since the last pass.
module ArticleLinkScrubber
  module_function

  # Returns a counts hash so callers can log it. Set `dry_run: true`
  # to count without writing.
  def run!(dry_run: false, limit: nil, verbose: false, logger: nil)
    sql = <<~SQL
      SELECT id, uid, url, content_html
      FROM articles
      WHERE content_html IS NOT NULL AND content_html <> ''
        AND content_scrubbed = FALSE
      ORDER BY id
      #{limit ? "LIMIT #{Integer(limit)}" : ''}
    SQL

    scanned = changed = unchanged = skipped = 0

    Database.connection.execute(sql).each do |row|
      scanned += 1
      url = row['url'].to_s
      # Need an absolute http(s) base for URI.join. Opaque GUID-style
      # `url` values (some older podcast feeds use the entry_id as a
      # fallback) can't anchor relative links — skip them cleanly.
      if url.empty? || !url.match?(%r{\Ahttps?://}i)
        skipped += 1
        unless dry_run
          Database.connection.execute(
            'UPDATE articles SET content_scrubbed = TRUE WHERE id = ?',
            [row['id']]
          )
        end
        next
      end

      before = row['content_html'].to_s
      after  = Sanitizer.sanitize_html(before, base_url: url)

      if after == before
        unchanged += 1
        unless dry_run
          Database.connection.execute(
            'UPDATE articles SET content_scrubbed = TRUE WHERE id = ?',
            [row['id']]
          )
        end
        next
      end

      changed += 1
      logger.info('article_link_scrub', event: 'changed', id: row['id'], uid: row['uid']) if logger && verbose

      next if dry_run

      Database.connection.execute(
        'UPDATE articles SET content_html = ?, content_scrubbed = TRUE WHERE id = ?',
        [after, row['id']]
      )
    end

    # Final pass: empty-content rows have nothing to scrub but were
    # filtered out of the SELECT above. Bump their flag so the
    # unscrubbed pool drains to zero.
    empty_marked = 0
    unless dry_run
      empty_marked = Database.connection.execute(<<~SQL).first['affected'].to_i rescue 0
        WITH bumped AS (
          UPDATE articles SET content_scrubbed = TRUE
          WHERE content_scrubbed = FALSE
            AND (content_html IS NULL OR content_html = '')
          RETURNING id
        )
        SELECT COUNT(*) AS affected FROM bumped
      SQL
    end

    remaining = Database.connection.execute(
      'SELECT COUNT(*) AS c FROM articles WHERE content_scrubbed = FALSE'
    ).first['c'].to_i

    {
      scanned:      scanned,
      changed:      changed,
      unchanged:    unchanged,
      skipped:      skipped,
      empty_marked: empty_marked,
      remaining:    remaining
    }
  end
end
