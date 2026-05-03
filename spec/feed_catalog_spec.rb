require_relative 'spec_helper'
require_relative '../app/feed_catalog'

RSpec.describe FeedCatalog do
  describe '.all' do
    it 'returns 31 curated entries (25 RSS + 6 podcasts)' do
      expect(FeedCatalog.all.length).to eq(31)
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

    it 'seeds the three most clearly tech-focused podcasts' do
      titles = FeedCatalog.seed_defaults
        .select { |e| e[:category] == :podcast }
        .map { |e| e[:title] }
      expect(titles).to contain_exactly(
        'The Changelog',
        'Software Engineering Daily',
        'Latent Space'
      )
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
