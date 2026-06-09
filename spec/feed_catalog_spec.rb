require_relative 'spec_helper'
require_relative '../app/feed_catalog'

RSpec.describe FeedCatalog do
  describe '.all' do
    it 'returns 172 curated entries (STUFF #89 — NPR + PBS adds 23 feeds)' do
      # 149 (previous) + 5 (npr_news) + 9 (npr_podcasts) + 5 (pbs_news) + 4 (pbs_shows) = 172.
      expect(FeedCatalog.all.length).to eq(172)
    end

    it 'every entry has the required keys' do
      FeedCatalog.all.each do |entry|
        expect(entry.keys).to include(:url, :title, :category, :interval, :seed, :blurb)
        expect(entry[:url]).to start_with('http')
        expect(entry[:title]).not_to be_empty
        expect(FeedCatalog::CATEGORIES.keys).to include(entry[:category])
      end
    end

    it 'has unique URLs' do
      urls = FeedCatalog.all.map { |e| e[:url] }
      expect(urls.uniq.length).to eq(urls.length)
    end
  end

  describe '.by_category' do
    it 'returns categories in the canonical order, every category present' do
      expect(FeedCatalog.by_category.keys).to eq(FeedCatalog::CATEGORIES.keys)
    end

    it 'every entry shows up under its declared category' do
      grouped = FeedCatalog.by_category
      FeedCatalog.all.each do |entry|
        expect(grouped[entry[:category]]).to include(entry)
      end
    end
  end

  describe '.seed_defaults' do
    it 'returns the entries flagged seed: true' do
      defaults = FeedCatalog.seed_defaults
      expect(defaults).to all(satisfy { |e| e[:seed] == true })
      expect(defaults.length).to be >= 3
    end
  end

  describe '.find_by_url' do
    it 'looks up an entry by exact URL match' do
      hn = FeedCatalog.find_by_url('https://news.ycombinator.com/rss')
      expect(hn[:title]).to eq('Hacker News')
    end

    it 'returns nil for an unknown URL' do
      expect(FeedCatalog.find_by_url('https://nope.example.com')).to be_nil
    end
  end
end
