require 'pg'
require 'monitor'

# Thin wrapper around PG::Connection that exposes a small SQL surface
# the rest of the app talks to via Database.connection:
#
#   db.execute(sql, args = [])       → Array<Hash> (or [])
#   db.execute_batch(sql)            → run multi-statement script
#   db.transaction { ... }           → BEGIN / COMMIT / ROLLBACK
#   db.last_insert_row_id            → id of the most recently
#                                      INSERTed row (via RETURNING)
#   db.changes                       → rows affected by last statement
#
# Placeholders: app SQL uses `?` throughout. The adapter rewrites each
# `?` (outside single-quoted strings) to PG's `$1, $2, …` form,
# left-to-right. No app SQL has `?` inside string literals so the
# simple rewriter is safe.
#
# Returning IDs: PG doesn't expose a "last insert id" on the
# connection; the canonical pattern is `RETURNING id`. `.execute`
# auto-appends `RETURNING id` to bare INSERTs (unless the SQL already
# has RETURNING or targets a no-id table) and exposes the value via
# `last_insert_row_id`.
#
# Thread safety + resilience: every @conn call is wrapped in a
# `Monitor` so the Puma worker's 5 threads don't desync the libpq
# protocol by interleaving exec_params on the same socket. (The pg
# gem has no per-connection mutex of its own.) Single-statement
# queries reconnect-once on a closed socket — DO managed PG drops
# idle connections after ~10 min, so the first query after a quiet
# stretch would otherwise throw `PG::UnableToSend` forever until the
# process restarted. Inside a transaction we deliberately don't
# retry — the BEGIN that opened the tx died on the dead socket, so
# transparently retrying on a fresh connection would silently turn a
# tx into a sequence of autocommit statements.
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

    # Run a parameterised query. Returns Array<Hash> for SELECTs (rows
    # as hashes keyed by column name), or [] for non-SELECTs.
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

    # Multi-statement helper. Used by Database.migrate! to run the .sql
    # migration files in db/migrations-postgres/.
    def execute_batch(sql)
      run_with_reconnect { |c| c.exec(sql) }
      nil
    end

    # BEGIN / COMMIT / ROLLBACK wrapper. Re-raises after ROLLBACK so the
    # caller sees the original error. Monitor is re-entrant, so nested
    # .execute calls inside the block re-acquire the same lock without
    # deadlocking.
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

    # `Database.reset!` calls this in tests.
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

    # Convert `?` placeholders to PG-style `$1, $2, …`.
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
      stock_quotes
    ].to_set.freeze

    def insert_without_returning?(sql)
      sql.match?(INSERT_RX) && !sql.match?(HAS_RETURNING_RX)
    end

    # Look at the target table name; skip auto-RETURN for no-id
    # tables. Conservative: if we can't extract a table name, assume
    # `id` exists.
    def insert_target_has_id?(sql)
      m = sql.match(INSERT_TARGET_RX)
      return true unless m
      !NO_ID_TABLES.include?(m[1].downcase)
    end
  end
end
