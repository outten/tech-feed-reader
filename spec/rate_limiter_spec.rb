require_relative 'spec_helper'
require_relative '../app/rate_limiter'

RSpec.describe RateLimiter do
  let(:ok_app) { ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['ok']] } }
  let(:middleware) { described_class.new(ok_app) }

  def env_for(method:, path:, ip: '203.0.113.1')
    Rack::MockRequest.env_for(path, method: method, 'REMOTE_ADDR' => ip)
  end

  it 'passes through unmatched paths' do
    100.times do
      status, = middleware.call(env_for(method: 'GET', path: '/articles'))
      expect(status).to eq(200)
    end
  end

  it 'passes through GET to a matched path (rules require POST)' do
    100.times do
      status, = middleware.call(env_for(method: 'GET', path: '/sign-in'))
      expect(status).to eq(200)
    end
  end

  it 'throttles POST /sign-in after 10 requests from the same IP' do
    statuses = 12.times.map do
      middleware.call(env_for(method: 'POST', path: '/sign-in')).first
    end
    expect(statuses.count(200)).to eq(10)
    expect(statuses.count(429)).to eq(2)
  end

  it 'throttles POST /sign-up after 5 requests from the same IP' do
    statuses = 8.times.map do
      middleware.call(env_for(method: 'POST', path: '/sign-up')).first
    end
    expect(statuses.count(200)).to eq(5)
    expect(statuses.count(429)).to eq(3)
  end

  it 'throttles POST /api/auth/* after 20 requests from the same IP' do
    statuses = 22.times.map do
      middleware.call(env_for(method: 'POST', path: '/api/auth/login/verify')).first
    end
    expect(statuses.count(200)).to eq(20)
    expect(statuses.count(429)).to eq(2)
  end

  it 'counts /sign-in and /sign-up separately (path-keyed)' do
    10.times { middleware.call(env_for(method: 'POST', path: '/sign-in')) }
    status, = middleware.call(env_for(method: 'POST', path: '/sign-up'))
    expect(status).to eq(200)
  end

  it 'counts IPs independently' do
    11.times { middleware.call(env_for(method: 'POST', path: '/sign-in', ip: '203.0.113.1')) }
    status, = middleware.call(env_for(method: 'POST', path: '/sign-in', ip: '203.0.113.2'))
    expect(status).to eq(200)
  end

  it 'returns a JSON body with the error key and a Retry-After header on throttle' do
    11.times { middleware.call(env_for(method: 'POST', path: '/sign-in')) }
    status, headers, body = middleware.call(env_for(method: 'POST', path: '/sign-in'))
    expect(status).to eq(429)
    expect(headers['Content-Type']).to eq('application/json')
    expect(headers['Retry-After']).to eq('300')
    expect(JSON.parse(body.first)).to include('error' => 'rate-limited')
  end
end
