require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feed_fetcher'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'

# Cache-only render contract — mirrors t-money-terminal's
# spec/portfolio_perf_spec.rb. The /dashboard, /articles, and
# /article/:id routes MUST NOT trigger a feed fetch on render. Network
# events only happen via the scheduler, /refresh/*, /feeds POST,
# and the user-initiated summarize button (TODO-K).
#
# If a future refactor accidentally fires FeedFetcher.fetch_feed during
# a page render, this spec fails immediately and points at the regression.
RSpec.describe 'cache-only render contract' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  before(:each) do
    feed = FeedsStore.add(url: 'https://example.com/feed.rss', title: 'Example')
    ArticlesStore.import(feed_id: feed['id'], entries: [
      {
        uid: 'aaaaaaaaaaaa', title: 'Article 1',
        url: 'https://example.com/1', author: 'A',
        published_at: '2026-05-02T12:00:00Z',
        content_html: '<p>One</p>', content_text: 'One'
      },
      {
        uid: 'bbbbbbbbbbbb', title: 'Article 2',
        url: 'https://example.com/2', author: 'B',
        published_at: '2026-05-01T12:00:00Z',
        content_html: '<p>Two</p>', content_text: 'Two'
      }
    ])
  end

  it '/dashboard does not call FeedFetcher.fetch_feed' do
    expect(FeedFetcher).not_to receive(:fetch_feed)
    get '/admin/dashboard'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Article 1')
  end

  it '/articles does not call FeedFetcher.fetch_feed' do
    expect(FeedFetcher).not_to receive(:fetch_feed)
    get '/articles'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Article 1')
    expect(last_response.body).to include('Article 2')
  end

  it '/articles?feed_id=N does not call FeedFetcher.fetch_feed' do
    feed_id = FeedsStore.all.first['id']
    expect(FeedFetcher).not_to receive(:fetch_feed)
    get "/articles?feed_id=#{feed_id}"
    expect(last_response.status).to eq(200)
  end

  it '/article/:id does not call FeedFetcher.fetch_feed' do
    expect(FeedFetcher).not_to receive(:fetch_feed)
    get '/article/aaaaaaaaaaaa'
    expect(last_response.status).to eq(200)
  end
end
