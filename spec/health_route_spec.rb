require_relative 'spec_helper'
require 'json'
require_relative '../app/main'

RSpec.describe 'GET /health' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  def body
    JSON.parse(last_response.body)
  end

  describe 'happy path' do
    before do
      # Don't actually call Redis in CI — Sidekiq.redis raises a real
      # connection error if no server is reachable. Stubbing it lets the
      # spec exercise the 200 + 'ok' branch deterministically.
      allow(Sidekiq).to receive(:redis).and_yield(double('redis').tap { |r| allow(r).to receive(:ping).and_return('PONG') })
      allow(Sidekiq::ProcessSet).to receive(:new).and_return(double('processes', size: 1))
    end

    it 'returns 200 with status=ok when every dep is up' do
      get '/health'
      expect(last_response.status).to eq(200)
      expect(body['status']).to eq('ok')
    end

    it 'includes version, git_sha, started_at, uptime, and current_time (TOD)' do
      get '/health'
      # STUFF #33A — `version` is the semver from /VERSION (e.g. 0.9.0);
      # `git_sha` is the commit hash from CI / `git rev-parse`.
      # Both surface so a deploy can be identified by semver in the
      # footer + by SHA in tracing.
      expect(body['version']).to match(/\A(\d+\.\d+\.\d+|unknown)\z/)
      expect(body['git_sha']).to be_a(String)
      expect(body['started_at']).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      expect(body['uptime_seconds']).to be >= 0
      expect(body['current_time']).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end

    it 'reports per-dependency status under checks{}' do
      get '/health'
      expect(body['checks']).to include('db', 'redis', 'sidekiq')
      expect(body.dig('checks', 'db', 'status')).to eq('ok')
      expect(body.dig('checks', 'redis', 'status')).to eq('ok')
      expect(body.dig('checks', 'sidekiq', 'status')).to eq('ok')
    end
  end

  describe 'when Redis is unreachable' do
    before do
      allow(Sidekiq).to receive(:redis).and_raise(StandardError, 'Connection refused - 127.0.0.1:6379')
      allow(Sidekiq::ProcessSet).to receive(:new).and_return(double('processes', size: 0))
    end

    it 'returns 200 with status=degraded (Redis is non-critical)' do
      get '/health'
      expect(last_response.status).to eq(200)
      expect(body['status']).to eq('degraded')
      expect(body.dig('checks', 'redis', 'status')).to eq('down')
      expect(body.dig('checks', 'redis', 'error')).to include('Connection refused')
    end
  end

  describe 'when SQLite is unreachable' do
    before do
      allow(Sidekiq).to receive(:redis).and_yield(double('redis').tap { |r| allow(r).to receive(:ping).and_return('PONG') })
      allow(Sidekiq::ProcessSet).to receive(:new).and_return(double('processes', size: 1))
      allow(Database).to receive(:connection).and_raise(StandardError, 'database is locked')
    end

    it 'returns 503 with status=fail' do
      get '/health'
      expect(last_response.status).to eq(503)
      expect(body['status']).to eq('fail')
      expect(body.dig('checks', 'db', 'status')).to eq('down')
    end
  end

  describe 'when Sidekiq has no workers running but Redis is up' do
    before do
      allow(Sidekiq).to receive(:redis).and_yield(double('redis').tap { |r| allow(r).to receive(:ping).and_return('PONG') })
      allow(Sidekiq::ProcessSet).to receive(:new).and_return(double('processes', size: 0))
    end

    it 'reports sidekiq status=no_workers but stays overall ok' do
      get '/health'
      expect(last_response.status).to eq(200)
      expect(body['status']).to eq('ok')
      expect(body.dig('checks', 'sidekiq', 'status')).to eq('no_workers')
      expect(body.dig('checks', 'sidekiq', 'workers')).to eq(0)
    end
  end

  it 'serves JSON regardless of Accept header' do
    allow(Sidekiq).to receive(:redis).and_yield(double('redis').tap { |r| allow(r).to receive(:ping).and_return('PONG') })
    allow(Sidekiq::ProcessSet).to receive(:new).and_return(double('processes', size: 1))

    get '/health', {}, { 'HTTP_ACCEPT' => 'text/html' }
    expect(last_response.headers['Content-Type']).to include('application/json')
  end
end
