require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/summary_store'

RSpec.describe '/article/:uid/summarize' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  let!(:feed) { FeedsStore.add(url: 'https://example.com/feed.rss') }
  let!(:article) do
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: 'a' * 12, title: 'Hello', url: 'https://example.com/a', author: nil,
      published_at: '2026-05-02T12:00:00Z',
      content_html: '<p>x</p>',
      content_text: 'First sentence about kubernetes. Second sentence is also about kubernetes. Third sentence is unrelated. Fourth sentence mentions kubernetes once more.'
    }])
    ArticlesStore.find_by_uid('a' * 12)
  end

  it 'auto-generates a summary at import time' do
    expect(SummaryStore.has_extractive?(article['id'])).to be(true)
  end

  it 'GET /article/:uid renders the cached summary above the body' do
    get "/article/#{article['uid']}"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Summary')
    expect(last_response.body).to include('First sentence')
  end

  it 'POST /article/:uid/summarize regenerates and redirects with notice=resummarized' do
    SummaryStore.upsert(article['id'], extractive: 'placeholder')

    post "/article/#{article['uid']}/summarize"
    expect(last_response.status).to eq(302)
    expect(last_response.headers['Location']).to include('notice=resummarized')

    fresh = SummaryStore.find(article['id'])
    expect(fresh['extractive']).not_to eq('placeholder')
    expect(fresh['extractive']).to include('First sentence')
  end

  it 'POST /article/:uid/summarize on an empty-body article reports error=empty-content' do
    empty_feed = FeedsStore.add(url: 'https://other.example.com/feed')
    ArticlesStore.import(feed_id: empty_feed['id'], entries: [{
      uid: 'b' * 12, title: 'Empty', url: 'https://other.example.com/b', author: nil,
      published_at: '2026-05-02T12:00:00Z',
      content_html: '', content_text: ''
    }])

    post "/article/#{'b' * 12}/summarize"
    expect(last_response.headers['Location']).to include('error=empty-content')
  end

  it '404s on an unknown uid' do
    post '/article/zzzzzzzzzzzz/summarize'
    expect(last_response.status).to eq(404)
  end
end
