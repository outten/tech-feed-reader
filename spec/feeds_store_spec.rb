require_relative 'spec_helper'
require_relative '../app/database'
require_relative '../app/feeds_store'
require_relative '../app/users_store'

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

  describe '.popular_by_type (STUFF #24)' do
    let(:db) { Database.connection }

    # Seed: 3 users (1 = default), 2 = kate, 3 = jane.
    # Catalog of feeds across the five buckets, with overlapping
    # subscriptions so the rank order is non-trivial.
    before do
      kate = UsersStore.create(username: 'kate')
      jane = UsersStore.create(username: 'jane')

      # NEWS — technology + general
      news_a = FeedsStore.add_to_catalog(url: 'https://news-a.example/rss', title: 'News A', topic: 'technology')
      news_b = FeedsStore.add_to_catalog(url: 'https://news-b.example/rss', title: 'News B', topic: 'general')
      news_c = FeedsStore.add_to_catalog(url: 'https://news-c.example/rss', title: 'News C', topic: 'technology')

      # SPORTS
      sport_a = FeedsStore.add_to_catalog(url: 'https://sport-a.example/rss', title: 'Sport A', topic: 'sports')
      sport_b = FeedsStore.add_to_catalog(url: 'https://sport-b.example/rss', title: 'Sport B', topic: 'sports')

      # NATURE
      nature_a = FeedsStore.add_to_catalog(url: 'https://nature-a.example/rss', title: 'Nature A', topic: 'nature')

      # YOUTUBE (channel-feed URL pattern)
      yt_a = FeedsStore.add_to_catalog(url: 'https://www.youtube.com/feeds/videos.xml?channel_id=UCAAA', title: 'YT A', topic: 'nature')
      yt_b = FeedsStore.add_to_catalog(url: 'https://www.youtube.com/feeds/videos.xml?channel_id=UCBBB', title: 'YT B', topic: 'sports')

      # PODCAST — signalled by an article with audio_url set
      pod_a = FeedsStore.add_to_catalog(url: 'https://pod-a.example/rss', title: 'Pod A', topic: 'technology')
      pod_b = FeedsStore.add_to_catalog(url: 'https://pod-b.example/rss', title: 'Pod B', topic: 'general')
      db.execute("INSERT INTO articles(uid, feed_id, title, url, audio_url) VALUES (?, ?, ?, ?, ?)",
                 ['pod_a_ep1', pod_a['id'], 'Ep 1', 'https://pod-a.example/ep1', 'https://pod-a.example/ep1.mp3'])
      db.execute("INSERT INTO articles(uid, feed_id, title, url, audio_url) VALUES (?, ?, ?, ?, ?)",
                 ['pod_b_ep1', pod_b['id'], 'Ep 1', 'https://pod-b.example/ep1', 'https://pod-b.example/ep1.mp3'])

      # Subscriptions: News A → 3, News B → 2, News C → 1.
      #                Sport A → 2, Sport B → 1.
      #                Nature A → 1.
      #                YT A → 2, YT B → 1.
      #                Pod A → 3, Pod B → 1.
      sub = ->(uid, fid) { FeedsStore.subscribe(uid, fid) }
      sub.call(1, news_a['id']); sub.call(kate['id'], news_a['id']); sub.call(jane['id'], news_a['id'])
      sub.call(1, news_b['id']); sub.call(kate['id'], news_b['id'])
      sub.call(1, news_c['id'])
      sub.call(1, sport_a['id']); sub.call(kate['id'], sport_a['id'])
      sub.call(1, sport_b['id'])
      sub.call(1, nature_a['id'])
      sub.call(1, yt_a['id']); sub.call(kate['id'], yt_a['id'])
      sub.call(1, yt_b['id'])
      sub.call(1, pod_a['id']); sub.call(kate['id'], pod_a['id']); sub.call(jane['id'], pod_a['id'])
      sub.call(1, pod_b['id'])
    end

    it 'ranks news feeds by subscriber count desc' do
      rows = FeedsStore.popular_by_type('news')
      expect(rows.map { |r| r['title'] }).to eq(['News A', 'News B', 'News C'])
      expect(rows.map { |r| r['subscriber_count'] }).to eq([3, 2, 1])
    end

    it 'excludes podcasts and youtube from the news bucket' do
      titles = FeedsStore.popular_by_type('news').map { |r| r['title'] }
      expect(titles).not_to include('Pod A', 'Pod B', 'YT A', 'YT B')
    end

    it 'ranks sports feeds and excludes the youtube sports channel' do
      rows = FeedsStore.popular_by_type('sports')
      expect(rows.map { |r| r['title'] }).to eq(['Sport A', 'Sport B'])
      expect(rows.map { |r| r['title'] }).not_to include('YT B')
    end

    it 'ranks nature feeds and excludes the youtube nature channel' do
      rows = FeedsStore.popular_by_type('nature')
      expect(rows.map { |r| r['title'] }).to eq(['Nature A'])
      expect(rows.map { |r| r['title'] }).not_to include('YT A')
    end

    it 'identifies podcasts by audio_url presence regardless of topic' do
      rows = FeedsStore.popular_by_type('podcasts')
      expect(rows.map { |r| r['title'] }).to eq(['Pod A', 'Pod B'])
      expect(rows.map { |r| r['subscriber_count'] }).to eq([3, 1])
    end

    it 'identifies youtube channels by URL pattern' do
      rows = FeedsStore.popular_by_type('youtube')
      expect(rows.map { |r| r['title'] }).to eq(['YT A', 'YT B'])
      expect(rows.map { |r| r['subscriber_count'] }).to eq([2, 1])
    end

    it 'honors the limit argument' do
      rows = FeedsStore.popular_by_type('news', limit: 2)
      expect(rows.length).to eq(2)
      expect(rows.map { |r| r['title'] }).to eq(['News A', 'News B'])
    end

    it 'returns an empty array for an unknown type' do
      expect(FeedsStore.popular_by_type('bogus')).to eq([])
    end
  end
end
