require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/read_state_store'

RSpec.describe 'article view + state-toggle routes' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  let(:uid)  { 'abc123def456' }
  let!(:feed) { FeedsStore.add(url: 'https://example.com/feed.rss', title: 'Example Tech') }
  let!(:article) do
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: uid, title: 'Hello',
      url: 'https://example.com/post', author: 'Jane',
      published_at: '2026-05-02T12:00:00Z',
      content_html: '<p>The body.</p>', content_text: 'The body.'
    }])
    ArticlesStore.find_by_uid(uid)
  end

  describe 'GET /article/:uid' do
    it 'renders the article and auto-marks it read' do
      get "/article/#{uid}"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('Hello')
      expect(last_response.body).to include('Example Tech')

      state = ReadStateStore.get(article['id'])
      expect(state['read']).to eq(1)
      expect(state['opened_at']).not_to be_nil
    end

    it '404s for an unknown uid' do
      get '/article/zzzzzzzzzzzz'
      expect(last_response.status).to eq(404)
      expect(last_response.body).to include('Article not found')
    end
  end

  describe 'POST /article/:uid/read' do
    it 'marks unread when read=0 is passed' do
      ReadStateStore.mark_read(article['id'])
      post "/article/#{uid}/read", { 'read' => '0' }
      expect(last_response.status).to eq(302)
      expect(ReadStateStore.get(article['id'])['read']).to eq(0)
    end

    it 'marks read when no read param is passed (default true)' do
      ReadStateStore.mark_read(article['id'], read: false)
      post "/article/#{uid}/read"
      expect(ReadStateStore.get(article['id'])['read']).to eq(1)
    end

    it 'honours return_to for redirect target' do
      post "/article/#{uid}/read", { 'return_to' => '/articles' }
      expect(last_response.headers['Location']).to include('/articles')
    end
  end

  describe 'POST /article/:uid/bookmark' do
    it 'flips bookmarked state' do
      post "/article/#{uid}/bookmark", { 'value' => '1' }
      expect(ReadStateStore.get(article['id'])['bookmarked']).to eq(1)
      post "/article/#{uid}/bookmark", { 'value' => '0' }
      expect(ReadStateStore.get(article['id'])['bookmarked']).to eq(0)
    end
  end

  describe 'POST /article/:uid/archive' do
    it 'flips archived state' do
      post "/article/#{uid}/archive", { 'value' => '1' }
      expect(ReadStateStore.get(article['id'])['archived']).to eq(1)
      post "/article/#{uid}/archive", { 'value' => '0' }
      expect(ReadStateStore.get(article['id'])['archived']).to eq(0)
    end
  end

  describe '/articles?state=' do
    let!(:read_article) do
      ArticlesStore.import(feed_id: feed['id'], entries: [{
        uid: 'r' * 12, title: 'Already read',
        url: 'https://example.com/r', author: nil,
        published_at: '2026-05-01T12:00:00Z',
        content_html: '<p>r</p>', content_text: 'r'
      }])
      r = ArticlesStore.find_by_uid('r' * 12)
      ReadStateStore.mark_read(r['id'])
      r
    end

    it 'state=unread excludes read articles' do
      get '/articles?state=unread'
      expect(last_response.body).to include('Hello')
      expect(last_response.body).not_to include('Already read')
    end

    it 'state=all includes both' do
      get '/articles?state=all'
      expect(last_response.body).to include('Hello')
      expect(last_response.body).to include('Already read')
    end

    it 'invalid state values fall back to :all' do
      get '/articles?state=bogus'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('Hello')
    end
  end
end
