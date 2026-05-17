require 'sqlite3'
require 'fileutils'
require 'set'
require_relative 'database/pg_adapter'

# Single shared DB handle for the app.
#
# Two backends: SQLite (default, dev + test + the current production
# Droplet) and PostgreSQL (opt-in via DATABASE_URL — Phase 5). The
# stores reach the DB via Database.connection, so the adapter
# abstraction lives in one place; stores stay backend-agnostic for
# the SQL we run.
#
# Replaces t-money's file-per-store pattern: instead of N JSON files each
# guarded by a per-store mutex + atomic-rename writes, we get one DB file
# with SQLite providing the atomicity. WAL mode lets the scheduler write
# while the web process reads without blocking.
#
# Usage:
#   Database.migrate!            # idempotent; safe to call on app boot
#   Database.connection          # SQLite3::Database OR Database::PgAdapter
#   Database.adapter             # :sqlite or :postgres
#   Database.reset!              # closes the handle (test teardown only)
#
# Migrations live in db/migrations/NNN_*.sql and are applied in filename
# order. Each migration runs in its own transaction so a half-failed run
# doesn't leave the DB in a wedged state. PG-dialect migrations land in
# db/migrations-postgres/ in D-PG-2.
module Database
  MUTEX = Mutex.new

  ROOT                    = File.expand_path('../..', __FILE__)
  MIGRATIONS_DIR_SQLITE   = File.join(ROOT, 'db', 'migrations')
  MIGRATIONS_DIR_POSTGRES = File.join(ROOT, 'db', 'migrations-postgres')
  # Kept for back-compat — some existing specs touch this constant.
  MIGRATIONS_DIR          = MIGRATIONS_DIR_SQLITE

  module_function

  # Path to the SQLite file. Test env uses an in-memory DB so each spec
  # run is hermetic; dev / production read and write data/app.db.
  def path
    if ENV['RACK_ENV'] == 'test'
      ':memory:'
    else
      File.join(ROOT, 'data', 'app.db')
    end
  end

  # :sqlite (default) or :postgres (when DATABASE_URL is set).
  # Memoised so callers can branch without re-parsing the env on every
  # access. Computed once per process (or once per Database.reset!).
  def adapter
    MUTEX.synchronize { @adapter ||= ENV['DATABASE_URL'].to_s.empty? ? :sqlite : :postgres }
  end

  def connection
    MUTEX.synchronize { @connection ||= open! }
  end

  # Test-only: drop the cached handle so the next connection call opens
  # fresh (used between in-memory specs to reset state).
  def reset!
    MUTEX.synchronize do
      @connection&.close
      @connection = nil
      @adapter    = nil
    end
  end

  # Apply every migration whose version isn't recorded in
  # schema_migrations. Returns the number of migrations applied. The
  # schema_migrations table is created here, not in the migration files,
  # so it's always present before we read it.
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

    pending = Dir[File.join(migrations_dir, '*.sql')].sort.reject do |f|
      applied.include?(File.basename(f, '.sql'))
    end

    pending.each do |file|
      version = File.basename(file, '.sql')
      sql     = File.read(file)
      db.transaction do
        db.execute_batch(sql)
        db.execute('INSERT INTO schema_migrations(version) VALUES (?)', [version])
      end
    end

    pending.length
  end

  # Adapter-aware migrations directory. SQLite reads the incremental
  # 001-024 sequence in db/migrations/; Postgres reads the consolidated
  # baseline in db/migrations-postgres/.
  def migrations_dir
    adapter == :postgres ? MIGRATIONS_DIR_POSTGRES : MIGRATIONS_DIR_SQLITE
  end

  class << self
    private

    def open!
      url = ENV['DATABASE_URL'].to_s
      return open_postgres!(url) unless url.empty?

      open_sqlite!
    end

    def open_sqlite!
      target = path
      unless target == ':memory:'
        FileUtils.mkdir_p(File.dirname(target))
      end

      db = SQLite3::Database.new(target)
      db.results_as_hash = true
      db.execute('PRAGMA journal_mode = WAL') unless target == ':memory:'
      db.execute('PRAGMA foreign_keys = ON')
      db.execute('PRAGMA synchronous = NORMAL')
      db
    end

    # Phase 5 / D-PG-1. Opens a PG::Connection from DATABASE_URL,
    # wraps it in our adapter so the rest of the app sees the same
    # surface it gets from SQLite3::Database. Migrations against PG
    # land in D-PG-2 (this PR doesn't ship the migration runner's PG
    # path yet — boot against PG will run the SQLite migration files,
    # which is wrong; D-PG-2 fixes this when the PG dialect migrations
    # exist).
    def open_postgres!(url)
      Database::PgAdapter.new(PG::Connection.new(url))
    end
  end
end
