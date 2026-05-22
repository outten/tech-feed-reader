require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'

# POST /refresh/all remains in use after the header button was removed
# (STUFF #51 follow-up — hourly cron now drives the same fan-out
# automatically). Surfaces that still post here: the /feeds page
# refresh button, the /admin/cache page, and the curl/scripted ops
# path. Spec locks the route's contract.
RSpec.describe 'POST /refresh/all' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  it 'enqueues a FeedRefreshWorker per feed and redirects to /feeds' do
    feed = FeedsStore.add(url: 'https://example.com/feed.rss', title: 'Example')
    expect(FeedRefreshWorker).to receive(:perform_async).with(feed['id'])

    post '/refresh/all'
    expect(last_response.status).to eq(302)
    expect(last_response.headers['Location']).to include('/feeds?notice=queued-all')
    expect(last_response.headers['Location']).to include('count=1')
  end
end
