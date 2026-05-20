require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'

RSpec.describe 'header refresh button' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  it 'renders the refresh form on every page' do
    %w[/admin/dashboard /topics /articles /feeds /tags /search /admin/cache /admin/health].each do |path|
      get path
      expect(last_response.body).to include('id="header-refresh"'), "missing on #{path}"
      expect(last_response.body).to include('action="/refresh/all"')
      expect(last_response.body).to include('Refresh all feeds')
    end
  end

  it 'enqueues a refresh job per feed when clicked' do
    feed = FeedsStore.add(url: 'https://example.com/feed.rss', title: 'Example')
    expect(FeedRefreshWorker).to receive(:perform_async).with(feed['id'])

    post '/refresh/all'
    expect(last_response.status).to eq(302)
    expect(last_response.headers['Location']).to include('/feeds?notice=queued-all')
    expect(last_response.headers['Location']).to include('count=1')
  end
end
