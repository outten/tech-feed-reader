require_relative 'spec_helper'
require_relative '../app/main'

RSpec.describe 'TechFeedReader smoke' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  # STUFF.md #13 — / always renders the public home page.
  it '/ renders the public home page for everyone' do
    get '/'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Stop swivel-chairing')
  end

  it 'renders /dashboard' do
    get '/dashboard'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Dashboard')
  end

  %w[/articles /topics /feeds /tags /search /admin/health /admin/cache].each do |path|
    it "renders #{path}" do
      get path
      expect(last_response.status).to eq(200)
    end
  end

  it 'renders /article/:uid for an existing article' do
    feed = FeedsStore.add(url: 'https://example.com/feed.rss', title: 'Example')
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: 'abc123def456', title: 'Hello',
      url: 'https://example.com/post', author: 'A',
      published_at: '2026-05-02T12:00:00Z',
      content_html: '<p>Body</p>', content_text: 'Body'
    }])

    get '/article/abc123def456'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Hello')
  end

  it 'returns 404 for an unknown article uid' do
    get '/article/zzzzzzzzzzzz'
    expect(last_response.status).to eq(404)
  end

  describe 'POST /feeds' do
    it 'adds a feed and redirects with notice=added' do
      post '/feeds', { url: 'https://example.com/rss', title: 'Example' }
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to include('/feeds?notice=added')
      expect(FeedsStore.find_by_url('https://example.com/rss')).not_to be_nil
    end

    it 'rejects malformed URLs with error=invalid-url' do
      post '/feeds', { url: 'not-a-url' }
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to include('/feeds?error=invalid-url')
      expect(FeedsStore.count).to eq(0)
    end

    it 'reports duplicate URLs with error=duplicate-url' do
      FeedsStore.add(url: 'https://dup.example.com/rss')
      post '/feeds', { url: 'https://dup.example.com/rss' }
      expect(last_response.headers['Location']).to include('/feeds?error=duplicate-url')
      expect(FeedsStore.count).to eq(1)
    end
  end

  describe 'POST /feeds/:id/delete' do
    it 'removes the feed and redirects with notice=removed' do
      feed = FeedsStore.add(url: 'https://gone.example.com/rss')
      post "/feeds/#{feed['id']}/delete"
      expect(last_response.headers['Location']).to include('/feeds?notice=removed')
      expect(FeedsStore.find(feed['id'])).to be_nil
    end

    it 'reports a missing feed with error=not-found' do
      post '/feeds/999/delete'
      expect(last_response.headers['Location']).to include('/feeds?error=not-found')
    end
  end

  describe 'POST /admin/refresh/:feed_id' do
    it 'enqueues a FeedRefreshWorker job and redirects with queued notice' do
      feed = FeedsStore.add(url: 'https://example.com/feed.rss')
      expect(FeedRefreshWorker).to receive(:perform_async).with(feed['id'])

      post "/admin/refresh/#{feed['id']}"
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to include('notice=queued')
      expect(last_response.headers['Location']).to include("feed_id=#{feed['id']}")
    end

    it 'reports not-found for an unknown feed id' do
      post '/admin/refresh/999'
      expect(last_response.headers['Location']).to include('error=not-found')
    end
  end

  describe 'POST /admin/refresh/all' do
    it 'enqueues one job per feed and redirects with the queued count' do
      a = FeedsStore.add(url: 'https://a.example.com/rss')
      b = FeedsStore.add(url: 'https://b.example.com/rss')
      expect(FeedRefreshWorker).to receive(:perform_async).with(a['id'])
      expect(FeedRefreshWorker).to receive(:perform_async).with(b['id'])

      post '/admin/refresh/all'
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to include('notice=queued-all')
      expect(last_response.headers['Location']).to include('count=2')
    end
  end
end
