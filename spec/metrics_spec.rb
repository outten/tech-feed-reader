require_relative 'spec_helper'
require_relative '../app/metrics'
require_relative '../app/metrics_middleware'
require_relative '../app/sidekiq_metrics_middleware'
require_relative '../app/main'

RSpec.describe Metrics do
  describe '.normalize_route' do
    it 'collapses /article/:uid' do
      expect(Metrics.normalize_route('/article/abc123def456')).to eq('/article/:uid')
    end

    it 'collapses article action sub-routes' do
      expect(Metrics.normalize_route('/article/abc123/read')).to eq('/article/:uid/read')
      expect(Metrics.normalize_route('/article/abc123/bookmark')).to eq('/article/:uid/bookmark')
      expect(Metrics.normalize_route('/article/abc123/summarize/llm')).to eq('/article/:uid/summarize/llm')
      expect(Metrics.normalize_route('/article/abc123/tag/42')).to eq('/article/:uid/tag/42')
    end

    it 'collapses /refresh/:id but keeps /refresh/all' do
      expect(Metrics.normalize_route('/refresh/42')).to eq('/refresh/:id')
      expect(Metrics.normalize_route('/refresh/all')).to eq('/refresh/all')
    end

    it 'collapses the API analogues' do
      expect(Metrics.normalize_route('/api/feeds/7')).to eq('/api/feeds/:id')
      expect(Metrics.normalize_route('/api/refresh/7')).to eq('/api/refresh/:id')
      expect(Metrics.normalize_route('/api/refresh/all')).to eq('/api/refresh/all')
    end

    it 'collapses /topics/:term and /tags/:id/delete' do
      expect(Metrics.normalize_route('/topics/llm')).to eq('/topics/:term')
      expect(Metrics.normalize_route('/tags/12/delete')).to eq('/tags/:id/delete')
    end

    it 'leaves stable routes alone' do
      %w[/dashboard /articles /podcasts /feeds /search /metrics /health].each do |p|
        expect(Metrics.normalize_route(p)).to eq(p)
      end
    end
  end
end

RSpec.describe MetricsMiddleware do
  let(:inner) { ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['ok']] } }
  let(:mw)    { MetricsMiddleware.new(inner) }

  it 'records the request count under the normalized route' do
    before_count = Metrics::HTTP_REQUESTS.get(labels: { method: 'GET', route: '/article/:uid', status: '200' })
    mw.call('REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/article/zzzz1111yyyy')
    after_count = Metrics::HTTP_REQUESTS.get(labels: { method: 'GET', route: '/article/:uid', status: '200' })
    expect(after_count - before_count).to eq(1)
  end

  it 'observes a non-negative duration into the histogram' do
    mw.call('REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/dashboard')
    sample = Metrics::HTTP_DURATION.get(labels: { method: 'GET', route: '/dashboard' })
    expect(sample['sum']).to be >= 0
    expect(sample['+Inf']).to be >= 1
  end
end

RSpec.describe SidekiqMetricsMiddleware do
  let(:worker) { double('Worker', class: double('WorkerClass', name: 'TestWorker')) }
  let(:mw)     { SidekiqMetricsMiddleware.new }

  it 'records success when the job returns normally' do
    before = Metrics::SIDEKIQ_JOBS.get(labels: { worker: 'TestWorker', status: 'success' })
    mw.call(worker, {}, 'default') { :result }
    after = Metrics::SIDEKIQ_JOBS.get(labels: { worker: 'TestWorker', status: 'success' })
    expect(after - before).to eq(1)
  end

  it 'records failed and re-raises when the job raises' do
    before = Metrics::SIDEKIQ_JOBS.get(labels: { worker: 'TestWorker', status: 'failed' })
    expect {
      mw.call(worker, {}, 'default') { raise 'boom' }
    }.to raise_error('boom')
    after = Metrics::SIDEKIQ_JOBS.get(labels: { worker: 'TestWorker', status: 'failed' })
    expect(after - before).to eq(1)
  end
end

RSpec.describe 'GET /metrics' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  before do
    # Stub Sidekiq calls that hit Redis so the spec stays hermetic.
    allow(Sidekiq::Stats).to receive(:new).and_return(double('stats', enqueued: 0))
    allow(Sidekiq::ProcessSet).to receive(:new).and_return(double('processes', size: 0))
  end

  it 'serves the Prometheus exposition text format' do
    get '/metrics'
    expect(last_response.status).to eq(200)
    expect(last_response.headers['Content-Type']).to start_with('text/plain')
    expect(last_response.headers['Content-Type']).to include('version=0.0.4')
  end

  it 'exposes the DB-derived gauges' do
    FeedsStore.add(url: 'https://example.com/feed.rss', title: 'Example')
    get '/metrics'
    expect(last_response.body).to include('tfr_feeds_subscribed 1')
    expect(last_response.body).to include('tfr_articles_total 0')
    expect(last_response.body).to match(/tfr_uptime_seconds \d+/)
  end

  it 'exposes counters and histograms with HELP + TYPE preambles' do
    get '/metrics'
    expect(last_response.body).to include('# HELP tfr_http_requests_total')
    expect(last_response.body).to include('# TYPE tfr_http_requests_total counter')
    expect(last_response.body).to include('# TYPE tfr_http_request_duration_seconds histogram')
    expect(last_response.body).to include('# TYPE tfr_feed_fetches_total counter')
    expect(last_response.body).to include('# TYPE tfr_sidekiq_jobs_total counter')
  end

  it 'still responds when Redis is unreachable' do
    allow(Sidekiq::Stats).to receive(:new).and_raise(StandardError, 'Connection refused')
    allow(Sidekiq::ProcessSet).to receive(:new).and_raise(StandardError, 'Connection refused')

    get '/metrics'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('tfr_feeds_subscribed')
  end
end
