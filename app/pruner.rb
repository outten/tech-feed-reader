require 'time'
require_relative 'database'
require_relative 'logger'

# Bounded-retention sweep over the `articles` table. Deletes anything
# whose effective publish date (`published_at`, falling back to
# `fetched_at`) is older than RETENTION_DAYS. The intent is storage
# hygiene: a single user reading a few feeds a day will accumulate
# thousands of stale rows in a few months, and we don't need them for
# the reading flow once the user has triaged them.
#
# Always preserved (regardless of age):
#   - Bookmarked articles. The user's explicit "I want this back"
#     signal — never sweep these.
#
# Optionally preserved (set PRUNE_KEEP_UNREAD=1):
#   - Unread articles. Cautious default behaviour for users who let
#     the inbox grow before triaging.
#
# Cascades: deleting from `articles` triggers ON DELETE CASCADE on
# read_state / summaries / article_tags, and the articles_fts AFTER
# DELETE trigger keeps the FTS5 index in sync. So this single DELETE
# is sufficient.
module Pruner
  DEFAULT_RETENTION_DAYS = 7

  Result = Struct.new(:deleted, :kept_bookmarked, :kept_unread, :cutoff, :retention_days, keyword_init: true)

  module_function

  # Effective retention window for the running process. Reads ENV
  # (set in .credentials / .env) and falls back to DEFAULT_RETENTION_DAYS.
  # Exposed so other surfaces (dashboard activity chart) can match
  # the prune window without re-implementing the env parse.
  def effective_retention_days
    raw = ENV['RETENTION_DAYS'].to_s.strip
    raw.match?(/\A\d+\z/) ? raw.to_i : DEFAULT_RETENTION_DAYS
  end

  # Returns a Result. `now` and `keep_unread` overridable for tests +
  # the env-var toggle the calling script reads.
  def prune_old(retention_days: DEFAULT_RETENTION_DAYS, keep_unread: false, now: Time.now.utc)
    cutoff = now - (retention_days * 86_400)
    cutoff_iso = cutoff.iso8601
    db = Database.connection

    # Counts before delete so the log + Result tell a complete story.
    kept_bookmarked = db.execute(<<~SQL, [cutoff_iso]).first['c']
      SELECT COUNT(*) AS c FROM articles a
      JOIN read_state rs ON rs.article_id = a.id
      WHERE rs.bookmarked = 1
        AND COALESCE(a.published_at, a.fetched_at) < ?
    SQL

    kept_unread = if keep_unread
      db.execute(<<~SQL, [cutoff_iso]).first['c']
        SELECT COUNT(*) AS c FROM articles a
        LEFT JOIN read_state rs ON rs.article_id = a.id
        WHERE COALESCE(rs.read, 0) = 0
          AND COALESCE(rs.bookmarked, 0) = 0
          AND COALESCE(a.published_at, a.fetched_at) < ?
      SQL
    else
      0
    end

    keep_clauses = ['COALESCE(rs.bookmarked, 0) = 1']
    keep_clauses << 'COALESCE(rs.read, 0) = 0' if keep_unread

    db.execute(<<~SQL, [cutoff_iso])
      DELETE FROM articles
      WHERE id IN (
        SELECT a.id FROM articles a
        LEFT JOIN read_state rs ON rs.article_id = a.id
        WHERE COALESCE(a.published_at, a.fetched_at) < ?
          AND NOT (#{keep_clauses.join(' OR ')})
      )
    SQL
    deleted = db.changes

    AppLogger.info('prune_articles',
                   deleted: deleted,
                   kept_bookmarked: kept_bookmarked,
                   kept_unread: kept_unread,
                   cutoff: cutoff_iso,
                   retention_days: retention_days)

    Result.new(
      deleted:         deleted,
      kept_bookmarked: kept_bookmarked,
      kept_unread:     kept_unread,
      cutoff:          cutoff_iso,
      retention_days:  retention_days
    )
  end
end
