require 'sqlite3'
require 'fileutils'
require 'set'

# Single shared SQLite handle for the app.
#
# Replaces t-money's file-per-store pattern: instead of N JSON files each
# guarded by a per-store mutex + atomic-rename writes, we get one DB file
# with SQLite providing the atomicity. WAL mode lets the scheduler write
# while the web process reads without blocking.
#
# Usage:
#   Database.migrate!            # idempotent; safe to call on app boot
#   Database.connection          # returns the shared SQLite3::Database
#   Database.reset!              # closes the handle (test teardown only)
#
# Migrations live in db/migrations/NNN_*.sql and are applied in filename
# order. Each migration runs in its own transaction so a half-failed run
# doesn't leave the DB in a wedged state.
module Database
  MUTEX = Mutex.new

  ROOT           = File.expand_path('../..', __FILE__)
  MIGRATIONS_DIR = File.join(ROOT, 'db', 'migrations')

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

  def connection
    MUTEX.synchronize { @connection ||= open! }
  end

  # Test-only: drop the cached handle so the next connection call opens
  # fresh (used between in-memory specs to reset state).
  def reset!
    MUTEX.synchronize do
      @connection&.close
      @connection = nil
    end
  end

  # Apply every migration whose version isn't recorded in
  # schema_migrations. Returns the number of migrations applied. The
  # schema_migrations table is created here, not in the migration files,
  # so it's always present before we read it.
  def migrate!
    db = connection
    db.execute_batch2(<<~SQL)
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
        db.execute_batch2(sql)
        db.execute('INSERT INTO schema_migrations(version) VALUES (?)', [version])
      end
    end

    pending.length
  end

  class << self
    private

    def open!
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
  end
end
