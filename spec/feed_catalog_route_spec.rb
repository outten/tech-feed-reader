require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/feed_catalog'

RSpec.describe '/feeds catalog routes' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  describe 'GET /feeds' do
    it 'renders the discover section with catalog entries grouped by category' do
      get '/feeds'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('Discover popular feeds')
      expect(last_response.body).to include('Hacker News')
      expect(last_response.body).to include('Tech publishers')
      expect(last_response.body).to include('+ Add')
    end

    it 'shows a "Subscribed" badge for already-added entries' do
      hn = FeedCatalog.find_by_url('https://news.ycombinator.com/rss')
      FeedsStore.add(url: hn[:url], title: hn[:title], fetch_interval_seconds: hn[:interval])

      get '/feeds'
      expect(last_response.body).to include('✓ Subscribed')
      # The HN row should not have an Add button (it's subscribed).
      hn_row = last_response.body[/Hacker News.*?(?=<\/li>)/m]
      expect(hn_row).to include('Subscribed')
      expect(hn_row).not_to include('+ Add')
    end
  end

  describe 'POST /feeds/catalog/add' do
    it 'adds a catalog entry by URL using its curated metadata' do
      post '/feeds/catalog/add', { 'url' => 'https://lobste.rs/rss' }
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to include('notice=catalog-added')
      expect(last_response.headers['Location']).to include('Lobsters')

      added = FeedsStore.find_by_url('https://lobste.rs/rss')
      expect(added['title']).to eq('Lobsters')
      expect(added['fetch_interval_seconds']).to eq(FeedsStore::HIGH_FREQUENCY_INTERVAL)
    end

    it 'redirects with already-subscribed notice when the URL is already in the table' do
      FeedsStore.add(url: 'https://news.ycombinator.com/rss', title: 'Hacker News')
      post '/feeds/catalog/add', { 'url' => 'https://news.ycombinator.com/rss' }
      expect(last_response.headers['Location']).to include('notice=already-subscribed')
    end

    it 'redirects with error=not-in-catalog for arbitrary URLs (no metadata-grease)' do
      post '/feeds/catalog/add', { 'url' => 'https://attacker.example.com/feed' }
      expect(last_response.headers['Location']).to include('error=not-in-catalog')
      expect(FeedsStore.find_by_url('https://attacker.example.com/feed')).to be_nil
    end
  end
end
