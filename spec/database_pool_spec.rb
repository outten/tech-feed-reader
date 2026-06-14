require_relative 'spec_helper'
require_relative '../app/database'
require_relative '../app/feeds_store'

# Phase 3 perf — connection pool. The web/worker processes now check a
# connection out of a pool per request/job (Database.with_connection) so
# concurrent threads each get their OWN PgAdapter instead of serializing
# on one shared connection. These specs exercise that directly (the suite
# itself runs on the single ambient connection).
RSpec.describe 'Database connection pool' do
  it 'returns the ambient connection outside with_connection, a pooled one inside' do
    ambient = Database.connection
    pooled  = Database.with_connection { Database.connection }
    expect(pooled).not_to equal(ambient)
    expect(Database.connection).to equal(ambient) # back to ambient after the block
  end

  it 'is re-entrant — a nested with_connection reuses the bound connection' do
    Database.with_connection do
      outer = Database.connection
      Database.with_connection do
        expect(Database.connection).to equal(outer)
      end
    end
  end

  it 'hands concurrent threads distinct connections' do
    seen  = []
    mutex = Mutex.new
    threads = 4.times.map do
      Thread.new do
        Database.with_connection do
          conn = Database.connection
          sleep 0.03 # hold it so the threads genuinely overlap
          mutex.synchronize { seen << conn.object_id }
        end
      end
    end
    threads.each(&:join)
    expect(seen.uniq.length).to be > 1
  end

  it 'isolates last_insert_row_id across concurrent inserts' do
    results = {}
    mutex   = Mutex.new
    threads = 5.times.map do |i|
      Thread.new do
        Database.with_connection do
          feed = FeedsStore.add_to_catalog(url: "https://pool.test/#{i}/#{rand(1_000_000)}")
          mutex.synchronize { results[i] = feed['id'] }
        end
      end
    end
    threads.each(&:join)

    ids = results.values
    expect(ids.uniq.length).to eq(5)                       # no cross-thread id contamination
    ids.each { |id| expect(FeedsStore.find(id)).not_to be_nil }
  end

  it 'keeps transactions isolated to the bound connection (rollback)' do
    feed = FeedsStore.add_to_catalog(url: 'https://pool.test/tx')
    expect do
      Database.with_connection do
        Database.connection.transaction do
          Database.connection.execute('DELETE FROM feeds WHERE id = ?', [feed['id']])
          raise 'boom'
        end
      end
    end.to raise_error('boom')
    expect(FeedsStore.find(feed['id'])).not_to be_nil # rollback restored it
  end
end
