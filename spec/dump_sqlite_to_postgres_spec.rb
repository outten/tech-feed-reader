require_relative 'spec_helper'
require_relative '../scripts/dump_sqlite_to_postgres'
require 'tempfile'
require 'stringio'

# Phase 5 / D-PG-4.5 — round-trip integration test for the cutover
# script. Only runs against PG (the suite's PG leg in CI); on SQLite
# there's no target backend, so the whole file is skipped.
RSpec.describe DumpSqliteToPostgres::Importer do
  before(:each) do
    skip 'D-PG-4.5 only meaningful with a PG target' unless Database.adapter == :postgres
  end

  # Build a temp SQLite file with the production migration chain
  # applied. Returns the path; the helper closes the handle so the
  # script can open its own (read-only) connection.
  def build_sqlite_source(&seed_block)
    file = Tempfile.create(['dump-src', '.sqlite'])
    file.close

    src = SQLite3::Database.new(file.path)
    src.results_as_hash = true
    src.execute('PRAGMA foreign_keys = ON')
    src.execute_batch(<<~SQL)
      CREATE TABLE schema_migrations (version TEXT PRIMARY KEY, applied_at TEXT);
    SQL
    Dir[File.join(Database::MIGRATIONS_DIR_SQLITE, '*.sql')].sort.each do |f|
      src.execute_batch(File.read(f))
      src.execute('INSERT OR IGNORE INTO schema_migrations(version) VALUES (?)',
                  [File.basename(f, '.sql')])
    end
    seed_block&.call(src)
    src.close
    file.path
  end

  def importer_for(sqlite_path)
    described_class.new(
      sqlite_path: sqlite_path,
      pg_url:      ENV['DATABASE_URL'],
      io:          StringIO.new
    )
  end

  describe 'empty source' do
    it 'completes without error and copies zero rows' do
      # The spec_helper seeded t-money into PG, and migration 022 in
      # the SQLite chain auto-seeds the same row into the source. Wipe
      # both so the populated-target gate passes AND the source has
      # genuinely nothing to copy.
      Database.connection.execute('DELETE FROM users')

      path = build_sqlite_source do |src|
        src.execute('DELETE FROM users')
      end
      importer_for(path).run!
      count = Database.connection.execute('SELECT COUNT(*) AS c FROM users').first['c'].to_i
      expect(count).to eq(0)
    ensure
      File.unlink(path) if path && File.exist?(path)
    end
  end

  describe 'populated source' do
    let(:source_path) do
      build_sqlite_source do |src|
        # The SQLite migration chain auto-seeds (1, 't-money'). Add a
        # second user so we exercise multi-row + sequence-bump.
        src.execute("INSERT INTO users(id, username, display_name) VALUES (2, 'alice', 'Alice')")
        src.execute("INSERT INTO feeds(id, url, title, topic) VALUES (1, 'https://example.com/feed', 'Example', 'general')")
        src.execute(<<~SQL, ['uid-aaaa-0001', 1, 'Hello world', 'https://example.com/p/1', 'Lorem ipsum dolor.'])
          INSERT INTO articles(uid, feed_id, title, url, content_text) VALUES (?, ?, ?, ?, ?)
        SQL
        src.execute('INSERT INTO read_state(user_id, article_id, read) VALUES (1, 1, 1)')
      end
    end

    before(:each) do
      # PG target needs to be empty for the script to consent to run.
      # spec_helper's before(:each) seeded users(id=1). Wipe + re-seq.
      Database.connection.execute('DELETE FROM users')
      Database.connection.execute("SELECT setval('users_id_seq', 1, false)")
    end

    after(:each) { File.unlink(source_path) if File.exist?(source_path) }

    it 'copies users, feeds, articles, and read_state into PG' do
      importer_for(source_path).run!

      users = Database.connection.execute('SELECT id, username FROM users ORDER BY id')
      expect(users.map { |r| [r['id'], r['username']] }).to eq([[1, 't-money'], [2, 'alice']])

      feeds = Database.connection.execute('SELECT id, url FROM feeds')
      expect(feeds.map { |r| r['url'] }).to eq(['https://example.com/feed'])

      articles = Database.connection.execute('SELECT id, uid, title FROM articles')
      expect(articles.first['uid']).to eq('uid-aaaa-0001')

      rs = Database.connection.execute('SELECT user_id, article_id, read FROM read_state')
      expect(rs).to eq([{ 'user_id' => 1, 'article_id' => 1, 'read' => 1 }])
    end

    it "bumps BIGSERIAL sequences past MAX(id) so the next app INSERT doesn't collide" do
      importer_for(source_path).run!

      # users now has id=1, id=2. Sequence must yield >= 3 on next nextval.
      next_id = Database.connection.execute("SELECT nextval('users_id_seq') AS n").first['n'].to_i
      expect(next_id).to be >= 3
    end

    it 'populates the generated tsv column on articles after import' do
      importer_for(source_path).run!

      hit = Database.connection.execute(<<~SQL)
        SELECT title FROM articles WHERE tsv @@ plainto_tsquery('english', 'lorem')
      SQL
      expect(hit.map { |r| r['title'] }).to eq(['Hello world'])
    end
  end

  describe 'populated target safety rail' do
    it 'refuses to run when the target PG already has rows' do
      # spec_helper seeded users(id=1, 't-money'). Leave it.
      path = build_sqlite_source
      expect { importer_for(path).run! }.to raise_error(/already has rows/)
    ensure
      File.unlink(path) if path && File.exist?(path)
    end
  end
end
