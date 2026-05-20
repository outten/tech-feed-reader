require_relative 'database/pg_adapter'

# Single shared DB handle for the app, backed by PostgreSQL.
#
# Usage:
#   Database.migrate!            # idempotent; safe to call on app boot
#   Database.connection          # Database::PgAdapter
#   Database.reset!              # closes the handle (test teardown only)
#
# Migrations live in db/migrations-postgres/NNN_*.sql and are applied in
# filename order. Each migration runs in its own transaction so a half-
# failed run doesn't leave the DB in a wedged state.
module Database
  MUTEX = Mutex.new

  ROOT           = File.expand_path('../..', __FILE__)
  MIGRATIONS_DIR = File.join(ROOT, 'db', 'migrations-postgres')

  module_function

  def connection
    MUTEX.synchronize { @connection ||= open! }
  end

  # Test-only: drop the cached handle so the next connection call opens
  # fresh (used between specs that explicitly reset the connection).
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
        # ON CONFLICT DO NOTHING — schema_migrations has no `id` column,
        # so the PG adapter's on_conflict? check skips its auto-RETURNING
        # append. Defensive against concurrent migrate! calls too.
        db.execute('INSERT INTO schema_migrations(version) VALUES (?) ON CONFLICT DO NOTHING', [version])
      end
    end

    pending.length
  end

  # Date-part of a TEXT ISO8601 or TIMESTAMP column. Used by:
  #   ArticlesStore.daily_counts
  #   ArticlesStore.state_query (topic-filtered windows)
  #   TopicClusters.recent (window cutoff)
  #   TagsStore.top_in_window
  #   PageviewsStore.daily_totals
  #   UsersStore.new_users_per_day
  def date_sql(column)
    "(#{column})::date"
  end

  class << self
    private

    def open!
      url = ENV['DATABASE_URL'].to_s
      raise 'DATABASE_URL is required (PostgreSQL connection string)' if url.empty?

      # PgAdapter owns the socket lifecycle when handed a URL string:
      # it opens the connection, runs `SET client_min_messages =
      # WARNING` + installs the type map, and reconnects-on-disconnect
      # if a Puma thread later trips over an idle-reaped socket.
      Database::PgAdapter.new(url)
    end
  end
end
