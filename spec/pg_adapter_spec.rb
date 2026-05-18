require_relative 'spec_helper'
require_relative '../app/database/pg_adapter'

# Phase 5 / D-PG-1. Unit-level coverage of Database::PgAdapter's
# wrapper behaviour. Uses a Struct-based stub of PG::Connection so
# the suite doesn't require a real Postgres in CI for this PR.
# (Real-PG integration coverage arrives in D-PG-2's CI matrix.)
RSpec.describe Database::PgAdapter do
  # Stub mimicking PG::Connection's surface the adapter touches.
  # Each `exec_params` / `exec` call is recorded so tests can
  # assert on the SQL the adapter sent.
  FakePgResult = Struct.new(:rows, :cmd_tuples) do
    def to_a; rows; end
  end

  class FakePgConn
    attr_reader :calls

    def initialize(scripted_results = {})
      @scripted = scripted_results # { sql_substring => FakePgResult }
      @calls    = []
    end

    def type_map_for_results=(_); end

    def exec_params(sql, args)
      @calls << [:exec_params, sql, args]
      match = @scripted.find { |key, _| sql.include?(key) }
      match ? match.last : FakePgResult.new([], 0)
    end

    def exec(sql)
      @calls << [:exec, sql]
      FakePgResult.new([], 0)
    end

    def close; end
  end

  describe '.execute — placeholder translation' do
    it 'rewrites ? to $1, $2 in left-to-right order' do
      conn    = FakePgConn.new
      adapter = described_class.new(conn)
      adapter.execute('SELECT * FROM articles WHERE feed_id = ? AND read = ?', [1, 0])
      _, sent_sql, sent_args = conn.calls.last
      expect(sent_sql).to include('feed_id = $1')
      expect(sent_sql).to include('read = $2')
      expect(sent_args).to eq([1, 0])
    end

    it 'leaves ? inside single-quoted strings alone' do
      conn    = FakePgConn.new
      adapter = described_class.new(conn)
      adapter.execute("SELECT * FROM articles WHERE title = 'is it?' AND feed_id = ?", [5])
      _, sent_sql, sent_args = conn.calls.last
      expect(sent_sql).to include("title = 'is it?'")     # literal ? preserved
      expect(sent_sql).to include('feed_id = $1')
      expect(sent_args).to eq([5])
    end

    it 'returns the result rows as an Array<Hash>' do
      result = FakePgResult.new([{ 'id' => 7, 'title' => 'Hello' }], 1)
      conn   = FakePgConn.new('SELECT' => result)
      adapter = described_class.new(conn)
      rows = adapter.execute('SELECT id, title FROM articles WHERE id = ?', [7])
      expect(rows).to eq([{ 'id' => 7, 'title' => 'Hello' }])
    end
  end

  describe '.execute — INSERT auto-RETURNING' do
    it 'auto-appends RETURNING id to bare INSERTs (preserves SQLite3#last_insert_row_id surface)' do
      result = FakePgResult.new([{ 'id' => 42 }], 1)
      conn   = FakePgConn.new('INSERT INTO feeds' => result)
      adapter = described_class.new(conn)
      adapter.execute('INSERT INTO feeds(url, title) VALUES (?, ?)',
                      ['https://x.com', 'X'])
      _, sent_sql, _ = conn.calls.last
      expect(sent_sql).to end_with('RETURNING id')
      expect(adapter.last_insert_row_id).to eq(42)
      expect(adapter.changes).to eq(1)
    end

    it 'leaves a user-supplied RETURNING clause alone (no double-append)' do
      result = FakePgResult.new([{ 'id' => 9 }], 1)
      conn   = FakePgConn.new('RETURNING id, url' => result)
      adapter = described_class.new(conn)
      adapter.execute('INSERT INTO feeds(url) VALUES (?) RETURNING id, url', ['x'])
      _, sent_sql, _ = conn.calls.last
      expect(sent_sql).to match(/RETURNING id, url\z/)
      expect(sent_sql).not_to match(/RETURNING id\s+RETURNING/)
      expect(adapter.last_insert_row_id).to eq(9)
    end

    it 'does NOT auto-append to no-id tables (read_state / mute_rules / etc.)' do
      conn    = FakePgConn.new
      adapter = described_class.new(conn)
      adapter.execute('INSERT INTO read_state(user_id, article_id, read) VALUES (?, ?, ?) ON CONFLICT DO NOTHING',
                      [1, 2, 1])
      _, sent_sql, _ = conn.calls.last
      expect(sent_sql).not_to include('RETURNING')
    end

    it 'DOES auto-append to id-bearing tables even when ON CONFLICT is present' do
      result = FakePgResult.new([{ 'id' => 99 }], 1)
      conn   = FakePgConn.new('INSERT INTO articles' => result)
      adapter = described_class.new(conn)
      adapter.execute('INSERT INTO articles(uid, feed_id, title, url) VALUES (?, ?, ?, ?) ON CONFLICT DO NOTHING',
                      ['abc', 1, 'x', 'http://x'])
      _, sent_sql, _ = conn.calls.last
      expect(sent_sql).to end_with('RETURNING id')
      expect(adapter.last_insert_row_id).to eq(99)
    end

    it 'opt-out via auto_return: false (for any caller that wants the old behaviour)' do
      conn    = FakePgConn.new
      adapter = described_class.new(conn)
      adapter.execute('INSERT INTO feeds(url) VALUES (?)', ['x'], auto_return: false)
      _, sent_sql, _ = conn.calls.last
      expect(sent_sql).not_to include('RETURNING')
    end

    it 'does NOT update last_insert_row_id on a SELECT that projects id' do
      result = FakePgResult.new([{ 'id' => 99 }], 1)
      conn   = FakePgConn.new('SELECT' => result)
      adapter = described_class.new(conn)
      expect(adapter.last_insert_row_id).to be_nil
      adapter.execute('SELECT id FROM feeds WHERE id = ?', [99])
      expect(adapter.last_insert_row_id).to be_nil  # no RETURNING → no update
    end
  end

  describe '.transaction' do
    # PG::BasicTypeMapForResults runs introspection SELECTs against
    # pg_type during adapter construction, polluting conn.calls. Filter
    # to transaction-control statements so these specs aren't fragile
    # against unrelated traffic.
    TX_KEYWORDS = %w[BEGIN COMMIT ROLLBACK].freeze
    def tx_calls(conn)
      conn.calls.map { |c| c[1] || c[0] }.select { |sql| TX_KEYWORDS.include?(sql) }
    end

    it 'wraps the block in BEGIN / COMMIT and yields self' do
      conn    = FakePgConn.new
      adapter = described_class.new(conn)
      received = nil
      adapter.transaction { |t| received = t }
      expect(tx_calls(conn)).to eq(%w[BEGIN COMMIT])
      expect(received).to be(adapter)
    end

    it 'ROLLBACKs and re-raises on a block-level exception' do
      conn    = FakePgConn.new
      adapter = described_class.new(conn)
      expect {
        adapter.transaction { raise 'boom' }
      }.to raise_error('boom')
      expect(tx_calls(conn)).to eq(%w[BEGIN ROLLBACK])
    end
  end

  # D-PG-5 production hardening. These only run on the PG leg because
  # they need a real PG::Connection to disconnect/reconnect against.
  describe 'thread safety + reconnect (PG leg only)' do
    before(:each) do
      skip 'Needs a real PG connection' unless Database.adapter == :postgres
    end

    it 'serialises concurrent execute calls across 10 threads without protocol desync' do
      # Pre-D-PG-5, 10 threads sharing one PG::Connection would
      # interleave exec_params on the socket and tip libpq into
      # PG::UnableToSend. Monitor serialises them; all 10 should
      # complete + their inserts should land.
      db = Database.connection
      db.execute('INSERT INTO feeds(url, title) VALUES (?, ?)',
                 ['https://example.com/parent', 'Parent'])
      feed_id = db.last_insert_row_id

      threads = 10.times.map do |i|
        Thread.new do
          db.execute(<<~SQL, ["uid-thread-#{i.to_s.rjust(3, '0')}", feed_id, "T#{i}", "https://example.com/t/#{i}"])
            INSERT INTO articles(uid, feed_id, title, url) VALUES (?, ?, ?, ?)
          SQL
        end
      end
      threads.each(&:join)

      count = db.execute('SELECT COUNT(*) AS c FROM articles WHERE feed_id = ?', [feed_id]).first['c'].to_i
      expect(count).to eq(10)
    end

    it 'reconnects after the underlying socket dies (idle-timeout simulation)' do
      db = Database.connection

      # Reach inside to slam the socket shut, mimicking DO's idle reaper.
      conn = db.instance_variable_get(:@conn)
      conn.close

      # Next query should not raise — adapter catches PG::UnableToSend,
      # re-opens a connection from the saved URL, retries the query.
      expect {
        rows = db.execute('SELECT 1 AS one')
        expect(rows.first['one']).to eq(1)
      }.not_to raise_error
    end

    it 'does NOT reconnect mid-transaction (would silently auto-commit subsequent statements)' do
      db = Database.connection

      expect {
        db.transaction do
          db.execute('INSERT INTO feeds(url, title) VALUES (?, ?)',
                     ['https://example.com/tx', 'Tx'])
          # Kill the socket from under the live transaction.
          db.instance_variable_get(:@conn).close
          db.execute('SELECT 1')   # this is the one that surfaces the death
        end
      }.to raise_error(PG::Error)

      # Adapter is still usable for new (autocommit) work after the dead
      # transaction unwinds — reconnect kicks in for the next execute.
      rows = db.execute('SELECT 1 AS one')
      expect(rows.first['one']).to eq(1)
    end
  end

  describe 'Database.connection switch' do
    it 'returns SQLite3::Database when DATABASE_URL is unset' do
      skip 'TEST_DATABASE_URL active — the suite is running against PG' if ENV['TEST_DATABASE_URL']
      expect(ENV['DATABASE_URL'].to_s).to eq('')
      expect(Database.connection).to be_a(SQLite3::Database)
      expect(Database.adapter).to eq(:sqlite)
    end

    it 'reports :postgres when DATABASE_URL is set' do
      prior = ENV['DATABASE_URL']
      Database.reset!
      ENV['DATABASE_URL'] = 'postgres://fake/db'
      expect(Database.adapter).to eq(:postgres)
    ensure
      # Restore the prior DATABASE_URL (set by spec_helper from
      # TEST_DATABASE_URL on the PG leg) so the next spec's
      # before(:each) reconnects to the real test PG, not the
      # fake URL we just set. Required since the spec_helper's
      # TRUNCATE optimization keeps the adapter alive across
      # examples — it can't fall back to SQLite if DATABASE_URL
      # is silently cleared.
      if prior
        ENV['DATABASE_URL'] = prior
      else
        ENV.delete('DATABASE_URL')
      end
      Database.reset!
    end
  end
end
