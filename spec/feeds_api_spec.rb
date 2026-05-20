require_relative 'spec_helper'
require 'json'
require_relative '../app/main'
require_relative '../app/feeds_store'

RSpec.describe 'feeds JSON API' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  def json
    JSON.parse(last_response.body)
  end

  describe 'POST /api/feeds' do
    it 'creates a feed and returns the row HTML' do
      post '/api/feeds', { url: 'https://example.com/rss', title: 'Example' }
      expect(last_response.status).to eq(201)
      expect(json['ok']).to eq(true)
      expect(json['feed']['url']).to eq('https://example.com/rss')
      expect(json['feed']['title']).to eq('Example')
      expect(json['row_html']).to include('<tr data-feed-id=')
      expect(json['row_html']).to include('https://example.com/rss')
      expect(FeedsStore.find_by_url('https://example.com/rss')).not_to be_nil
    end

    it 'rejects malformed URLs with 422 + invalid-url' do
      post '/api/feeds', { url: 'not-a-url' }
      expect(last_response.status).to eq(422)
      expect(json['ok']).to eq(false)
      expect(json['error']).to eq('invalid-url')
      expect(FeedsStore.count).to eq(0)
    end

    it 'rejects duplicates with 422 + duplicate-url' do
      FeedsStore.add(url: 'https://dup.example.com/rss')
      post '/api/feeds', { url: 'https://dup.example.com/rss' }
      expect(last_response.status).to eq(422)
      expect(json['error']).to eq('duplicate-url')
    end
  end

  describe 'DELETE /api/feeds/:id' do
    it 'unsubscribes the user and returns ok (catalog row remains)' do
      feed = FeedsStore.add(url: 'https://gone.example.com/rss')
      delete "/api/feeds/#{feed['id']}"
      expect(last_response.status).to eq(200)
      expect(json['ok']).to eq(true)
      expect(json['id']).to eq(feed['id'])
      # A2: DELETE /api/feeds/:id now unsubscribes, doesn't delete from
      # the catalog (someone else might still subscribe).
      expect(FeedsStore.subscribed?(1, feed['id'])).to be(false)
      expect(FeedsStore.find(feed['id'])).not_to be_nil
    end

    it 'returns 404 + not-found for an unknown id' do
      delete '/api/feeds/9999'
      expect(last_response.status).to eq(404)
      expect(json['error']).to eq('not-found')
    end
  end

  describe 'POST /api/feeds/catalog/add' do
    let(:catalog_url) do
      require_relative '../app/feed_catalog'
      FeedCatalog.all.first[:url]
    end

    it 'subscribes a catalog entry with status=added' do
      post '/api/feeds/catalog/add', { url: catalog_url }
      expect(last_response.status).to eq(201)
      expect(json['ok']).to eq(true)
      expect(json['status']).to eq('added')
      expect(json['row_html']).to include(catalog_url)
      expect(FeedsStore.find_by_url(catalog_url)).not_to be_nil
    end

    it 'returns status=already-subscribed when the URL is in FeedsStore' do
      FeedsStore.add(url: catalog_url, title: 'Pre-existing')
      post '/api/feeds/catalog/add', { url: catalog_url }
      expect(last_response.status).to eq(200)
      expect(json['ok']).to eq(true)
      expect(json['status']).to eq('already-subscribed')
    end

    it 'rejects URLs not in the curated catalog with 422 + not-in-catalog' do
      post '/api/feeds/catalog/add', { url: 'https://random.example.com/feed.xml' }
      expect(last_response.status).to eq(422)
      expect(json['error']).to eq('not-in-catalog')
    end
  end

  describe 'POST /api/refresh/all' do
    it 'enqueues one job per feed and reports the queued count' do
      a = FeedsStore.add(url: 'https://a.example.com/rss')
      b = FeedsStore.add(url: 'https://b.example.com/rss')
      expect(FeedRefreshWorker).to receive(:perform_async).with(a['id'])
      expect(FeedRefreshWorker).to receive(:perform_async).with(b['id'])

      post '/api/refresh/all'
      expect(last_response.status).to eq(200)
      expect(json).to eq('ok' => true, 'queued' => 2)
    end
  end

  describe 'POST /api/refresh/:feed_id' do
    it 'enqueues a single job and returns the feed id' do
      feed = FeedsStore.add(url: 'https://example.com/rss')
      expect(FeedRefreshWorker).to receive(:perform_async).with(feed['id'])

      post "/api/refresh/#{feed['id']}"
      expect(last_response.status).to eq(200)
      expect(json).to eq('ok' => true, 'feed_id' => feed['id'])
    end

    it 'returns 404 + not-found for an unknown feed id' do
      post '/api/refresh/9999'
      expect(last_response.status).to eq(404)
      expect(json['error']).to eq('not-found')
    end
  end
end
