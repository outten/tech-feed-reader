require 'pg'

# Phase 5 / D-PG-1. Thin wrapper around PG::Connection that exposes
# the same surface SQLite3::Database does, so the rest of the app
# can stay backend-agnostic at the Database.connection layer:
#
#   db.execute(sql, args = [])       → Array<Hash> (or [])
#   db.execute_batch(sql)            → run multi-statement script
#   db.transaction { ... }           → BEGIN / COMMIT / ROLLBACK
#   db.last_insert_row_id            → id of the most recently
#                                      INSERTed row (via RETURNING)
#   db.changes                       → rows affected by last statement
#
# Placeholders: stores use SQLite's `?` style throughout. This
# adapter rewrites each `?` (outside single-quoted strings) to
# Postgres's `$1, $2, …` form, left-to-right, before sending the
# query. None of the existing app SQL has `?` inside string
# literals so the simple rewriter is safe.
#
# Returning IDs: PG doesn't expose a "last insert id" on the
# connection; the canonical pattern is `RETURNING id`. To preserve
# the SQLite3::Database surface, this adapter auto-appends
# `RETURNING id` to any INSERT that doesn't already have a
# RETURNING clause, stashes the returned id, and surfaces it from
# `last_insert_row_id`. Tables with composite PKs (no `id` column)
# would break under auto-append — those tables (read_state,
# feed_feedback, etc.) never call last_insert_row_id today, so
# this is safe; D-PG-3 audits to confirm. If a future table
# without `id` needs INSERT, pass `auto_return: false` to skip.
module Database
  class PgAdapter
    def initialize(conn)
      @conn = conn
      @conn.type_map_for_results = PG::BasicTypeMapForResults.new(@conn)
      @last_insert_row_id = nil
      @changes            = 0
    end

    # Run a parameterised query. Returns Array<Hash> for SELECTs
    # (matches SQLite3::Database with results_as_hash=true), or [] for
    # non-SELECTs (callers that care about result rows check this
    # length; callers that just want side-effect Hold .execute and
    # ignore the return value).
    def execute(sql, args = [], auto_return: true)
      pg_sql = translate_placeholders(sql)
      if auto_return && insert_without_returning?(pg_sql)
        pg_sql = "#{pg_sql.sub(/\s*;\s*\z/, '')} RETURNING id"
      end

      result = @conn.exec_params(pg_sql, Array(args))
      @changes = result.cmd_tuples
      rows = result.to_a

      if rows.any? && rows.first.key?('id') && pg_sql.match?(/\bRETURNING\b/i)
        # Only update last_insert_row_id when the statement explicitly
        # returned an id (either user-supplied RETURNING or our
        # auto-append). Avoids clobbering after a SELECT that happens
        # to project an `id` column.
        @last_insert_row_id = rows.last['id']
      end

      rows
    end

    # Multi-statement helper. Mirrors SQLite3::Database#execute_batch.
    # Used by Database.migrate! to run the .sql migration files; D-PG-2
    # ships a Postgres-side migrations directory.
    def execute_batch(sql)
      @conn.exec(sql)
      nil
    end

    # Same shape as SQLite3::Database#transaction. Re-raises after
    # ROLLBACK so the caller sees the original error.
    def transaction
      @conn.exec('BEGIN')
      begin
        yield self
      rescue StandardError
        @conn.exec('ROLLBACK')
        raise
      else
        @conn.exec('COMMIT')
      end
    end

    def last_insert_row_id
      @last_insert_row_id
    end

    def changes
      @changes
    end

    # `Database.reset!` calls this in tests. Mirrors SQLite3::Database#close.
    def close
      @conn&.close
    end

    private

    # Convert SQLite-style `?` placeholders to PG-style `$1, $2, …`.
    # Walks the string once; toggles `in_string` whenever a single
    # quote is seen (PG's escape for a literal single quote is `''`
    # which the walker handles naturally — the second quote re-toggles
    # back). `?` outside strings becomes `$<n>`; inside strings it's
    # left alone.
    def translate_placeholders(sql)
      out      = +''
      in_string = false
      counter   = 0
      sql.each_char do |c|
        if c == "'"
          in_string = !in_string
          out << c
        elsif c == '?' && !in_string
          counter += 1
          out << "$#{counter}"
        else
          out << c
        end
      end
      out
    end

    # Detect a bare INSERT statement (no RETURNING) so we can append one
    # for last_insert_row_id support. Conservative: only matches a
    # leading INSERT keyword with no RETURNING anywhere downstream.
    INSERT_RX            = /\A\s*INSERT\b/i
    HAS_RETURNING_RX     = /\bRETURNING\b/i

    def insert_without_returning?(sql)
      sql.match?(INSERT_RX) && !sql.match?(HAS_RETURNING_RX)
    end
  end
end
