require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/health_registry'

RSpec.describe 'admin pages' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  describe 'GET /admin' do
    it 'renders system overview with counts, db size, and integration rows' do
      FeedsStore.add(url: 'https://example.com/feed.rss', title: 'Example')

      get '/admin'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('System overview')
      expect(last_response.body).to include('Feeds')
      expect(last_response.body).to include('Articles')
      expect(last_response.body).to include('Database')
      expect(last_response.body).to include('Claude (LLM summarizer)')
      expect(last_response.body).to include('Sidekiq (background refresh)')
      expect(last_response.body).to include('/admin/sidekiq')
    end
  end

  describe 'GET /admin/cache' do
    it 'renders the empty state when no feeds exist' do
      get '/admin/cache'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('No feeds subscribed')
    end

    it 'lists every feed with its article count and last status' do
      feed = FeedsStore.add(url: 'https://example.com/feed.rss', title: 'Example')
      ArticlesStore.import(feed_id: feed['id'], entries: [{
        uid: 'a' * 12, title: 'A', url: 'https://example.com/a',
        author: nil, published_at: '2026-05-02T12:00:00Z',
        content_html: '<p>x</p>', content_text: 'x'
      }])
      FeedsStore.update(feed['id'], last_status: '200', last_fetched_at: Time.now.utc.iso8601)

      get '/admin/cache'
      expect(last_response.body).to include('Example')
      expect(last_response.body).to include('200')
      expect(last_response.body).to match(/<td[^>]*>1<\/td>/) # one article
    end
  end

  describe 'GET /admin/health' do
    it 'shows the no-op note in test env unless HEALTH_REGISTRY=1' do
      get '/admin/health'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('no-op in this env')
      expect(last_response.body).to include('No observations yet')
    end

    it 'renders observations + summary when the registry is enabled' do
      ENV['HEALTH_REGISTRY'] = '1'
      feed = FeedsStore.add(url: 'https://example.com/feed.rss', title: 'Live feed')
      HealthRegistry.record(feed_id: feed['id'], status: :ok,    latency_ms: 120)
      HealthRegistry.record(feed_id: feed['id'], status: :error, latency_ms: 200, note: 'Net::ReadTimeout')

      get '/admin/health'
      expect(last_response.body).to include('Live feed')
      expect(last_response.body).to include('120ms')
      expect(last_response.body).to include('Net::ReadTimeout')
    ensure
      ENV.delete('HEALTH_REGISTRY')
    end
  end

  describe 'dashboard degraded banner' do
    it 'is hidden when HealthRegistry.degraded? is false' do
      get '/dashboard'
      expect(last_response.body).not_to include('Feeds are systematically failing')
    end

    it 'appears when HealthRegistry.degraded? is true' do
      ENV['HEALTH_REGISTRY'] = '1'
      HealthRegistry::DEGRADED_WINDOW.times do
        HealthRegistry.record(feed_id: 1, status: :error, latency_ms: 0)
      end

      get '/dashboard'
      expect(last_response.body).to include('Feeds are systematically failing')
    ensure
      ENV.delete('HEALTH_REGISTRY')
    end
  end
end
