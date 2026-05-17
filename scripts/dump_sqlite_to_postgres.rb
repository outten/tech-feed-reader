#!/usr/bin/env ruby
# Phase 5 / D-PG-4.5. One-shot dump of a SQLite snapshot into a
# fresh managed-PostgreSQL target.
#
# Usage:
#   DATABASE_URL=postgresql://doadmin:…@cluster:25060/tfr?sslmode=require \
#     ruby scripts/dump_sqlite_to_postgres.rb path/to/data.sqlite
#
# Assumes the target PG already has the consolidated schema migrated
# in (run `DATABASE_URL=… ruby scripts/migrate.rb` first). Refuses to
# run if any target table already has rows — re-running needs a clean
# slate.
#
# Tables are walked in declaration order so FK parents land before
# their children. After insert, BIGSERIAL sequences are bumped past
# MAX(id) for each id-bearing table — otherwise the next INSERT from
# the app would collide on id=1.

require 'sqlite3'
require 'pg'

module DumpSqliteToPostgres
  # Order matches db/migrations-postgres/001_init.sql declaration order
  # (users → feeds → articles → …). Don't reorder without re-checking
  # FK targets.
  TABLES = %w[
    users
    webauthn_credentials
    recovery_codes
    feeds
    user_feed_subscriptions
    feed_feedback
    articles
    read_state
    tags
    article_tags
    summaries
    mute_rules
    digests
    triages
    sports_leagues
    sports_teams
    sports_matches
    sports_players
    sports_follows
    sports_standings
    sports_entity_articles
    background_pool
    llm_usage
  ].freeze

  # Subset of TABLES that have a BIGSERIAL `id` column. Composite-PK
  # tables and background_pool (INTEGER PRIMARY KEY, not BIGSERIAL)
  # are excluded — they have no `<table>_id_seq` to bump.
  ID_SEQ_TABLES = %w[
    users
    webauthn_credentials
    recovery_codes
    feeds
    user_feed_subscriptions
    articles
    tags
    digests
    triages
    sports_leagues
    sports_teams
    sports_matches
    sports_players
    sports_follows
    sports_standings
    llm_usage
  ].freeze

  # PG-generated columns we must NOT include in the INSERT — the
  # target re-derives them from the source columns.
  GENERATED_COLUMNS = {
    'articles' => %w[tsv]
  }.freeze

  class Importer
    def initialize(sqlite_path:, pg_url:, io: $stdout)
      @sqlite_path = sqlite_path
      @pg_url      = pg_url
      @io          = io
    end

    def run!
      open_connections!
      refuse_if_target_populated!
      @pg.transaction do |pg|
        TABLES.each { |t| copy_table(pg, t) }
        ID_SEQ_TABLES.each { |t| bump_sequence(pg, t) }
      end
      @io.puts 'Done.'
    ensure
      @sqlite&.close
      @pg&.close
    end

    private

    def open_connections!
      @sqlite = SQLite3::Database.new(@sqlite_path, readonly: true)
      @sqlite.results_as_hash = true
      @pg = PG.connect(@pg_url)
    end

    def refuse_if_target_populated!
      populated = TABLES.each_with_object({}) do |t, acc|
        c = @pg.exec("SELECT COUNT(*) AS c FROM #{t}").first['c'].to_i
        acc[t] = c if c.positive?
      end
      return if populated.empty?

      raise <<~MSG.chomp
        Refusing to run: target PG already has rows in #{populated.keys.join(', ')}.
        (#{populated.map { |t, c| "#{t}=#{c}" }.join(', ')})
        Drop & re-migrate the target, then re-run.
      MSG
    end

    def copy_table(pg, table)
      rows = @sqlite.execute("SELECT * FROM #{table}")
      if rows.empty?
        @io.puts "  #{table}: 0 rows (skipped)"
        return
      end

      # SQLite3#results_as_hash returns hashes keyed by BOTH integer
      # positions and column names. Keep only the name keys.
      cols = rows.first.keys.select { |k| k.is_a?(String) }
      cols -= GENERATED_COLUMNS.fetch(table, [])

      quoted_cols  = cols.map { |c| %("#{c}") }.join(', ')
      placeholders = cols.each_index.map { |i| "$#{i + 1}" }.join(', ')
      sql = "INSERT INTO #{table} (#{quoted_cols}) VALUES (#{placeholders})"

      stmt_name = "ins_#{table}"
      pg.prepare(stmt_name, sql)
      rows.each { |row| pg.exec_prepared(stmt_name, cols.map { |c| row[c] }) }
      @io.puts "  #{table}: #{rows.size} rows"
    end

    def bump_sequence(pg, table)
      pg.exec(<<~SQL)
        SELECT setval('#{table}_id_seq',
                      GREATEST(1, COALESCE((SELECT MAX(id) FROM #{table}), 1)))
      SQL
    end
  end
end

if $PROGRAM_NAME == __FILE__
  sqlite_path = ARGV[0] || ENV['SQLITE_PATH']
  abort "usage: #{$PROGRAM_NAME} <sqlite-path>  (or set SQLITE_PATH)" unless sqlite_path
  abort 'DATABASE_URL must point at the target managed-PG cluster' unless ENV['DATABASE_URL']
  abort "SQLite file not found: #{sqlite_path}" unless File.exist?(sqlite_path)

  DumpSqliteToPostgres::Importer.new(
    sqlite_path: sqlite_path,
    pg_url:      ENV['DATABASE_URL']
  ).run!
end
