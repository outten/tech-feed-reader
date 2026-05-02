require_relative 'spec_helper'
require_relative '../app/database'
require_relative '../app/feeds_store'

RSpec.describe FeedsStore do
  before(:each) do
    Database.reset!
    Database.migrate!
  end
  after(:each) { Database.reset! }

  describe '.add' do
    it 'inserts a new feed and returns the row' do
      feed = FeedsStore.add(url: 'https://example.com/rss', title: 'Example')
      expect(feed['id']).to be > 0
      expect(feed['url']).to eq('https://example.com/rss')
      expect(feed['title']).to eq('Example')
      expect(feed['fetch_interval_seconds']).to eq(FeedsStore::PUBLISHER_INTERVAL)
    end

    it 'accepts a custom fetch_interval_seconds' do
      feed = FeedsStore.add(
        url: 'https://news.ycombinator.com/rss',
        title: 'Hacker News',
        fetch_interval_seconds: FeedsStore::HIGH_FREQUENCY_INTERVAL
      )
      expect(feed['fetch_interval_seconds']).to eq(900)
    end

    it 'rejects a duplicate URL via the UNIQUE constraint' do
      FeedsStore.add(url: 'https://example.com/rss')
      expect {
        FeedsStore.add(url: 'https://example.com/rss')
      }.to raise_error(SQLite3::ConstraintException, /UNIQUE/)
    end
  end

  describe '.all and .count' do
    it 'returns rows in id order; count tracks length' do
      expect(FeedsStore.count).to eq(0)
      FeedsStore.add(url: 'https://a.example.com/rss', title: 'A')
      FeedsStore.add(url: 'https://b.example.com/rss', title: 'B')

      titles = FeedsStore.all.map { |f| f['title'] }
      expect(titles).to eq(%w[A B])
      expect(FeedsStore.count).to eq(2)
    end
  end

  describe '.find and .find_by_url' do
    it 'returns nil for unknown id / url' do
      expect(FeedsStore.find(999)).to be_nil
      expect(FeedsStore.find_by_url('https://nope.example.com')).to be_nil
    end

    it 'returns the row for known id / url' do
      f = FeedsStore.add(url: 'https://example.com/rss', title: 'Example')
      expect(FeedsStore.find(f['id'])['url']).to eq('https://example.com/rss')
      expect(FeedsStore.find_by_url('https://example.com/rss')['id']).to eq(f['id'])
    end
  end

  describe '.update' do
    it 'updates allowed columns and returns the fresh row' do
      f = FeedsStore.add(url: 'https://example.com/rss', title: 'Example')
      updated = FeedsStore.update(
        f['id'],
        title: 'Renamed',
        last_etag: 'W/"abc123"',
        last_modified: 'Fri, 02 May 2026 12:00:00 GMT',
        last_status: '200',
        last_fetched_at: '2026-05-02T12:00:00Z'
      )
      expect(updated['title']).to eq('Renamed')
      expect(updated['last_etag']).to eq('W/"abc123"')
      expect(updated['last_status']).to eq('200')
    end

    it 'silently ignores unknown columns' do
      f = FeedsStore.add(url: 'https://example.com/rss', title: 'Example')
      expect {
        FeedsStore.update(f['id'], bogus_column: 'nope')
      }.not_to raise_error
      expect(FeedsStore.find(f['id'])['title']).to eq('Example')
    end
  end

  describe '.remove' do
    it 'deletes the feed and cascades to its articles' do
      f = FeedsStore.add(url: 'https://example.com/rss', title: 'Example')
      Database.connection.execute(<<~SQL, ['abc123def456', f['id'], 'Hi', 'https://example.com/post'])
        INSERT INTO articles(uid, feed_id, title, url) VALUES (?, ?, ?, ?)
      SQL

      expect(FeedsStore.remove(f['id'])).to be(true)
      expect(FeedsStore.find(f['id'])).to be_nil
      orphan_count = Database.connection
        .execute('SELECT COUNT(*) AS c FROM articles')
        .first['c']
      expect(orphan_count).to eq(0)
    end

    it 'returns false when no row matches' do
      expect(FeedsStore.remove(999)).to be(false)
    end
  end
end
