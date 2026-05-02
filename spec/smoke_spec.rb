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

  %w[/articles /feeds /tags /search /admin/health /admin/cache].each do |path|
    it "renders #{path}" do
      get path
      expect(last_response.status).to eq(200)
    end
  end

  it 'renders /article/:id' do
    get '/article/abc123'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('abc123')
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
end
