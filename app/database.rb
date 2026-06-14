require 'connection_pool'
require_relative 'database/pg_adapter'

# DB access for the app, backed by PostgreSQL.
#
# Two access paths share one PgAdapter-per-connection model:
#
#   • Request / job scope — `Database.with_connection { ... }` checks a
#     connection out of a pool and binds it to the current thread for the
#     duration of the block (Rack middleware per request, Sidekiq server
#     middleware per job). Inside, `Database.connection` returns that
#     bound connection, so a request's transactions + last_insert_row_id
#     all run on the same adapter, and concurrent Puma threads each get
#     their OWN connection (no more single-connection serialization).
#
#   • Ambient (everything else) — boot, `Database.migrate!`, scripts, and
#     the test suite run single-threaded and call `Database.connection`
#     without a bound connection. They share one long-lived adapter,
#     kept SEPARATE from the request pool so it never starves Puma
#     threads. Same behaviour the app had before pooling.
#
# Migrations live in db/migrations-postgres/NNN_*.sql, applied in
# filename order; each runs in its own transaction.
module Database
  MUTEX = Mutex.new
  THREAD_KEY = :tfr_db_conn

  DEFAULT_POOL_SIZE    = 5
  DEFAULT_POOL_TIMEOUT = 5

  ROOT           = File.expand_path('../..', __FILE__)
  MIGRATIONS_DIR = File.join(ROOT, 'db', 'migrations-postgres')

  module_function

  # The connection for the current unit of work: the request/job-bound
  # one if `with_connection` set it, otherwise the shared ambient handle.
  def connection
    Thread.current[THREAD_KEY] || ambient_connection
  end

  # Check a pooled connection out and bind it to this thread for the
  # block, then return it to the pool. Re-entrant: a nested call reuses
  # the already-bound connection (and does NOT check it in early).
  def with_connection
    return yield if Thread.current[THREAD_KEY]

    pool.with do |conn|
      Thread.current[THREAD_KEY] = conn
      begin
        yield
      ensure
        Thread.current[THREAD_KEY] = nil
      end
    end
  end

  # Test-only: drop every handle so the next call opens fresh. Closes
  # the ambient adapter and shuts the pool down.
  def reset!
    MUTEX.synchronize do
      Thread.current[THREAD_KEY] = nil
      @ambient&.close
      @ambient = nil
      @pool&.shutdown { |c| c.close }
      @pool = nil
    end
  end

  def pool_size
    (ENV['DB_POOL'] || DEFAULT_POOL_SIZE).to_i
  end

  # Apply every migration whose version isn't recorded in
  # schema_migrations. Returns the number applied. (Unchanged from the
  # pre-pool version; runs on the ambient connection at boot.)
  def migrate!
    db = connection
    db.execute_batch(<<~SQL)
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version    TEXT PRIMARY KEY,
        applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
    SQL

    applied = db
      .execute('SELECT version FROM schema_migrations')
      .map { |r| r['version'] }
      .to_set

    pending = Dir[File.join(MIGRATIONS_DIR, '*.sql')].sort.reject do |f|
      applied.include?(File.basename(f, '.sql'))
    end

    pending.each do |file|
      version = File.basename(file, '.sql')
      sql     = File.read(file)
      db.transaction do
        db.execute_batch(sql)
        db.execute('INSERT INTO schema_migrations(version) VALUES (?) ON CONFLICT DO NOTHING', [version])
      end
    end

    pending.length
  end

  # Date-part of a TEXT ISO8601 or TIMESTAMP column.
  def date_sql(column)
    "(#{column})::date"
  end

  class << self
    private

    def pool
      MUTEX.synchronize do
        @pool ||= ConnectionPool.new(size: pool_size, timeout: DEFAULT_POOL_TIMEOUT) { build_adapter }
      end
    end

    def ambient_connection
      MUTEX.synchronize { @ambient ||= build_adapter }
    end

    def build_adapter
      url = ENV['DATABASE_URL'].to_s
      raise 'DATABASE_URL is required (PostgreSQL connection string)' if url.empty?

      # PgAdapter owns the socket lifecycle (open, SET client_min_messages,
      # type map, reconnect-on-disconnect). Each pooled connection is its
      # own adapter with its own PG::Connection + Monitor + state.
      Database::PgAdapter.new(url)
    end
  end
end
