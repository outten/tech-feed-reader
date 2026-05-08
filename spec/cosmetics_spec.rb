require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/pruner'
require_relative '../app/providers/itunes_lookup'
require_relative '../app/request_log_middleware'

# Cosmetics PR — covers items 5, 6, 7. Items 1-4 are pure CSS and
# don't get unit tests (visually verified instead).

# ---------- Item 5: dashboard activity-chart window matches RETENTION ----

RSpec.describe Pruner, '.effective_retention_days' do
  it 'returns DEFAULT_RETENTION_DAYS when ENV is unset' do
    ENV.delete('RETENTION_DAYS')
    expect(Pruner.effective_retention_days).to eq(Pruner::DEFAULT_RETENTION_DAYS)
  end

  it 'parses ENV[RETENTION_DAYS] when set to an integer string' do
    ENV['RETENTION_DAYS'] = '14'
    expect(Pruner.effective_retention_days).to eq(14)
  ensure
    ENV.delete('RETENTION_DAYS')
  end

  it 'falls back to default for non-integer values' do
    ENV['RETENTION_DAYS'] = 'banana'
    expect(Pruner.effective_retention_days).to eq(Pruner::DEFAULT_RETENTION_DAYS)
  ensure
    ENV.delete('RETENTION_DAYS')
  end
end

RSpec.describe 'GET /dashboard activity chart' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  def seed_one_article
    feed = FeedsStore.add(url: 'https://x.com/dash', title: 'Dash')
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: 'dashtest0001', title: 'A', url: 'https://x.com/1', author: nil,
      published_at: '2026-05-06T12:00:00Z',
      content_html: '<p>x</p>', content_text: 'x',
      audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
    }])
  end

  it 'labels the chart with the actual retention window (default 7 days)' do
    seed_one_article
    get '/dashboard'
    expect(last_response.body).to include('Activity (last 7 days)')
    expect(last_response.body).not_to include('Activity (last 30 days)')
  end

  it 'reflects RETENTION_DAYS env override in the heading' do
    ENV['RETENTION_DAYS'] = '14'
    seed_one_article
    get '/dashboard'
    expect(last_response.body).to include('Activity (last 14 days)')
  ensure
    ENV.delete('RETENTION_DAYS')
  end
end

# ---------- Item 6: Providers::ITunesLookup ----------------------------

RSpec.describe Providers::ITunesLookup do
  def stub_response(status:, body:)
    Struct.new(:code, :body).new(status.to_s, body)
  end

  it 'returns :ok with artworkUrl600 on a happy-path search' do
    body = JSON.generate(
      resultCount: 1,
      results: [{
        'collectionName' => 'The Ezra Klein Show',
        'artworkUrl100'  => 'https://example.com/100x100.jpg',
        'artworkUrl600'  => 'https://example.com/600x600.jpg'
      }]
    )
    result = Providers::ITunesLookup.find_artwork('The Ezra Klein Show',
                                                  http_get: ->(_url) { stub_response(status: 200, body: body) })
    expect(result.status).to eq(:ok)
    expect(result.artwork_url).to eq('https://example.com/600x600.jpg')
    expect(result.collection_name).to eq('The Ezra Klein Show')
  end

  it 'falls back to artworkUrl100 when 600 is missing' do
    body = JSON.generate(results: [{ 'collectionName' => 'Some Show', 'artworkUrl100' => 'https://example.com/100.jpg' }])
    result = Providers::ITunesLookup.find_artwork('Some Show',
                                                  http_get: ->(_url) { stub_response(status: 200, body: body) })
    expect(result.artwork_url).to eq('https://example.com/100.jpg')
  end

  it 'returns :not_found when iTunes has no matches' do
    body = JSON.generate(resultCount: 0, results: [])
    result = Providers::ITunesLookup.find_artwork('No Such Podcast Anywhere',
                                                  http_get: ->(_url) { stub_response(status: 200, body: body) })
    expect(result.status).to eq(:not_found)
  end

  it 'prefers an exact title match over the first result' do
    body = JSON.generate(results: [
      { 'collectionName' => 'The Ezra Klein Show — Greatest Hits', 'artworkUrl600' => 'https://example.com/spinoff.jpg' },
      { 'collectionName' => 'The Ezra Klein Show',                  'artworkUrl600' => 'https://example.com/canonical.jpg' }
    ])
    result = Providers::ITunesLookup.find_artwork('The Ezra Klein Show',
                                                  http_get: ->(_url) { stub_response(status: 200, body: body) })
    expect(result.artwork_url).to eq('https://example.com/canonical.jpg')
  end

  it 'returns :error on non-200 HTTP' do
    result = Providers::ITunesLookup.find_artwork('whatever',
                                                  http_get: ->(_url) { stub_response(status: 503, body: '') })
    expect(result.status).to eq(:error)
    expect(result.error).to include('503')
  end

  it 'returns :error on malformed JSON' do
    result = Providers::ITunesLookup.find_artwork('whatever',
                                                  http_get: ->(_url) { stub_response(status: 200, body: 'not json') })
    expect(result.status).to eq(:error)
    expect(result.error).to include('JSON parse')
  end

  it 'returns :not_found for blank input' do
    result = Providers::ITunesLookup.find_artwork('   ',
                                                  http_get: ->(_url) { raise 'should not be called' })
    expect(result.status).to eq(:not_found)
  end
end

# ---------- Item 7: RequestLogMiddleware ------------------------------

RSpec.describe RequestLogMiddleware::App do
  let(:io)         { StringIO.new }
  let(:downstream) { ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['ok']] } }
  let(:middleware) { RequestLogMiddleware::App.new(downstream) }

  before do
    AppLogger.reset!(io: io)
    AppLogger.instance.level = ::Logger::DEBUG
  end

  after do
    AppLogger.reset!
  end

  def lines
    io.string.lines.map { |l| JSON.parse(l) }
  end

  it 'emits one http_request line per call with method/path/status/latency' do
    middleware.call('REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/articles', 'QUERY_STRING' => '', 'REMOTE_ADDR' => '127.0.0.1')
    line = lines.last
    expect(line['event']).to eq('http_request')
    expect(line['method']).to eq('GET')
    expect(line['path']).to eq('/articles')
    expect(line['status']).to eq(200)
    expect(line['latency_ms']).to be_a(Integer)
    expect(line['ip']).to eq('127.0.0.1')
  end

  it 'omits the query field when QUERY_STRING is empty' do
    middleware.call('REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/feeds', 'QUERY_STRING' => '', 'REMOTE_ADDR' => '1.2.3.4')
    expect(lines.last).not_to include('query')
  end

  it 'includes query when present' do
    middleware.call('REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/articles', 'QUERY_STRING' => 'state=unread', 'REMOTE_ADDR' => '1.2.3.4')
    expect(lines.last['query']).to eq('state=unread')
  end

  it 'logs static-asset requests too (not just dynamic routes)' do
    middleware.call('REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/style.css', 'QUERY_STRING' => 'v=1', 'REMOTE_ADDR' => '1.2.3.4')
    line = lines.last
    expect(line['path']).to eq('/style.css')
  end

  it 'prefers HTTP_X_FORWARDED_FOR over REMOTE_ADDR for ip when present' do
    middleware.call(
      'REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/', 'QUERY_STRING' => '',
      'REMOTE_ADDR' => '10.0.0.1', 'HTTP_X_FORWARDED_FOR' => '203.0.113.42'
    )
    expect(lines.last['ip']).to eq('203.0.113.42')
  end
end

# ---------- Item 7: AppLogger default level by env --------------------

RSpec.describe AppLogger, 'default level by env (Cosmetics 7)' do
  before { AppLogger.reset! }
  after  { AppLogger.reset! }

  it 'defaults to DEBUG when RACK_ENV is unset' do
    saved = ENV['RACK_ENV']
    ENV.delete('RACK_ENV')
    ENV.delete('LOG_LEVEL')
    expect(AppLogger.instance.level).to eq(::Logger::DEBUG)
  ensure
    ENV['RACK_ENV'] = saved if saved
  end

  it 'defaults to DEBUG when RACK_ENV=development' do
    saved = ENV['RACK_ENV']
    ENV['RACK_ENV'] = 'development'
    ENV.delete('LOG_LEVEL')
    expect(AppLogger.instance.level).to eq(::Logger::DEBUG)
  ensure
    ENV['RACK_ENV'] = saved if saved
  end

  it 'defaults to INFO for staging' do
    saved = ENV['RACK_ENV']
    ENV['RACK_ENV'] = 'staging'
    ENV.delete('LOG_LEVEL')
    expect(AppLogger.instance.level).to eq(::Logger::INFO)
  ensure
    ENV['RACK_ENV'] = saved if saved
  end

  it 'defaults to INFO for production' do
    saved = ENV['RACK_ENV']
    ENV['RACK_ENV'] = 'production'
    ENV.delete('LOG_LEVEL')
    expect(AppLogger.instance.level).to eq(::Logger::INFO)
  ensure
    ENV['RACK_ENV'] = saved if saved
  end

  it 'defaults to FATAL for test (so RSpec stays clean)' do
    expect(AppLogger.instance.level).to eq(::Logger::FATAL)
  end

  it 'LOG_LEVEL still wins over the env default' do
    saved = ENV['RACK_ENV']
    ENV['RACK_ENV'] = 'production'
    ENV['LOG_LEVEL'] = 'debug'
    expect(AppLogger.instance.level).to eq(::Logger::DEBUG)
  ensure
    ENV['RACK_ENV'] = saved if saved
    ENV.delete('LOG_LEVEL')
  end
end
