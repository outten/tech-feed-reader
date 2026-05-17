require 'pg'
require 'monitor'

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
# the SQLite3::Database surface, this adapter accepts an opt-in
# `auto_return: true` keyword on .execute that appends `RETURNING
# id` if the SQL doesn't already have a RETURNING clause, stashes
# the returned id, and surfaces it from `last_insert_row_id`.
# Default is `false` (safe for composite-PK tables like
# schema_migrations / read_state / mute_rules where there is no
# `id` column). Stores that today read `db.last_insert_row_id`
# after a bare INSERT get audited in D-PG-3 and switched to
# `execute(..., auto_return: true)`.
#
# Thread safety + resilience (D-PG-5 production fix): every @conn
# call is wrapped in a `Monitor` so the Puma worker's 5 threads
# don't desync the libpq protocol by interleaving exec_params on
# the same socket. (Sqlite3-ruby has its own per-connection mutex,
# which is why the SQLite era never tripped this; the pg gem does
# not.) Single-statement queries also reconnect-once on a closed
# socket — DO managed PG drops idle connections after ~10 min, so
# the first query after a quiet stretch would otherwise throw
# `PG::UnableToSend` forever until the process restarted. Inside a
# transaction we deliberately don't retry — the BEGIN that opened
# the tx died on the dead socket, so transparently retrying on a
# fresh connection would silently turn a tx into a sequence of
# autocommit statements.
module Database
  class PgAdapter
    RECOVERABLE = [PG::UnableToSend, PG::ConnectionBad].freeze

    # Accepts either a connection-string URL (production path —
    # adapter owns the socket lifecycle and can reconnect) or a
    # pre-built PG::Connection (the test-suite path — specs hand in
    # a fake; reconnect-on-disconnect is disabled there because we
    # have nowhere to reconnect to).
    def initialize(url_or_conn)
      if url_or_conn.is_a?(String)
        @url  = url_or_conn
        @conn = open_conn
      else
        @url  = nil
        @conn = url_or_conn
        configure_conn(@conn)
      end
      @monitor = Monitor.new
      @in_tx   = false
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
      if auto_return && insert_without_returning?(pg_sql) && insert_target_has_id?(pg_sql)
        pg_sql = "#{pg_sql.sub(/\s*;\s*\z/, '')} RETURNING id"
      end

      result = run_with_reconnect { |c| c.exec_params(pg_sql, Array(args)) }
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
      run_with_reconnect { |c| c.exec(sql) }
      nil
    end

    # Same shape as SQLite3::Database#transaction. Re-raises after
    # ROLLBACK so the caller sees the original error. Monitor is
    # re-entrant, so nested .execute calls inside the block re-acquire
    # the same lock without deadlocking.
    def transaction
      @monitor.synchronize do
        @conn.exec('BEGIN')
        @in_tx = true
        begin
          yield self
        rescue StandardError
          (@conn.exec('ROLLBACK') rescue nil)
          raise
        else
          @conn.exec('COMMIT')
        ensure
          @in_tx = false
        end
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
      @monitor.synchronize { @conn&.close }
    end

    private

    # Send a single statement under the connection monitor. If the
    # socket is dead and we're not in a transaction, close + re-open
    # + retry once. Inside a transaction we re-raise: the BEGIN died
    # with the socket, so retrying would silently auto-commit each
    # subsequent statement on the fresh connection. Adapters built
    # without a URL (specs with FakePgConn) can't reconnect — also
    # re-raise.
    def run_with_reconnect
      @monitor.synchronize do
        begin
          yield @conn
        rescue *RECOVERABLE
          raise if @in_tx || @url.nil?
          (@conn.close rescue nil)
          @conn = open_conn
          yield @conn
        end
      end
    end

    def open_conn
      conn = PG::Connection.new(@url)
      configure_conn(conn)
      conn
    end

    def configure_conn(conn)
      # Mute NOTICE-level chatter (`SET client_min_messages = WARNING`)
      # and install the type map so result columns come back as the
      # right Ruby types (Integer for int8, etc.) without a per-row
      # decode pass in callers.
      conn.exec('SET client_min_messages = WARNING')
      conn.type_map_for_results = PG::BasicTypeMapForResults.new(conn)
    end

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
    INSERT_TARGET_RX     = /\A\s*INSERT\s+INTO\s+([A-Za-z_][A-Za-z0-9_]*)/i

    # Tables that lack an `id` column: composite-PK + a few PK-on-
    # another-column tables. Auto-appending `RETURNING id` to inserts
    # against these errors with `column "id" does not exist`.
    # Stores that need a returned key on these tables use SELECT
    # afterward — none today rely on last_insert_row_id for them.
    NO_ID_TABLES = %w[
      schema_migrations
      background_pool
      read_state
      mute_rules
      feed_feedback
      article_tags
      sports_entity_articles
      summaries
    ].to_set.freeze

    def insert_without_returning?(sql)
      sql.match?(INSERT_RX) && !sql.match?(HAS_RETURNING_RX)
    end

    # Look at the target table name; skip auto-RETURN for no-id
    # tables. Conservative: if we can't extract a table name, assume
    # `id` exists (matches SQLite3's silent-no-op-on-missing-column
    # behaviour upon last_insert_row_id access).
    def insert_target_has_id?(sql)
      m = sql.match(INSERT_TARGET_RX)
      return true unless m
      !NO_ID_TABLES.include?(m[1].downcase)
    end
  end
end
