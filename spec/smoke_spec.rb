require_relative 'spec_helper'
require_relative '../app/main'

RSpec.describe 'TechFeedReader smoke' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  it 'redirects / → /dashboard' do
    get '/'
    expect(last_response.status).to eq(302)
    expect(last_response.headers['Location']).to include('/dashboard')
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
    let(:rss_body) { File.read(File.expand_path('fixtures/rss20.xml', __dir__)) }

    it 'fetches, imports, and redirects with refresh status' do
      feed     = FeedsStore.add(url: 'https://example.com/feed.rss')
      response = instance_double(Net::HTTPSuccess, code: '200', body: rss_body)
      allow(response).to receive(:[]) { |_| nil }
      allow(Providers::HttpClient).to receive(:get).and_return(response)

      post "/admin/refresh/#{feed['id']}"
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to include('notice=refreshed')
      expect(last_response.headers['Location']).to include('status=ok')
      expect(last_response.headers['Location']).to include('imported=2')
      expect(ArticlesStore.count).to eq(2)
    end

    it 'reports not-found for an unknown feed id' do
      post '/admin/refresh/999'
      expect(last_response.headers['Location']).to include('error=not-found')
    end
  end

  describe 'POST /admin/refresh/all' do
    let(:rss_body) { File.read(File.expand_path('fixtures/rss20.xml', __dir__)) }

    it 'iterates every feed and reports the summary' do
      FeedsStore.add(url: 'https://a.example.com/rss')
      FeedsStore.add(url: 'https://b.example.com/rss')
      response = instance_double(Net::HTTPSuccess, code: '200', body: rss_body)
      allow(response).to receive(:[]) { |_| nil }
      allow(Providers::HttpClient).to receive(:get).and_return(response)

      post '/admin/refresh/all'
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to include('notice=refreshed-all')
      expect(last_response.headers['Location']).to include('ok=2')
      expect(last_response.headers['Location']).to include('imported=4')
    end
  end
end
