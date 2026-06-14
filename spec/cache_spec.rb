require_relative 'spec_helper'
require_relative '../app/cache'

# The cache is bypassed in RACK_ENV=test (see Cache.enabled?), so these
# specs force it on and stub the redis-client with a fake to exercise the
# real GET / SET / parse / graceful-degradation logic without a server.
RSpec.describe Cache do
  let(:fake) { instance_double('RedisClient::Pooled') }

  before do
    allow(Cache).to receive(:enabled?).and_return(true)
    allow(Cache).to receive(:client).and_return(fake)
  end

  describe '.fetch' do
    it 'miss → runs the block, SETs the JSON value with TTL, returns it' do
      allow(fake).to receive(:call).with('GET', 'k').and_return(nil)
      expect(fake).to receive(:call).with('SET', 'k', '[1,2,3]', 'EX', 60)
      ran = false
      expect(Cache.fetch('k', ttl: 60) { ran = true; [1, 2, 3] }).to eq([1, 2, 3])
      expect(ran).to be true
    end

    it 'hit → returns the parsed cached value and does NOT run the block' do
      allow(fake).to receive(:call).with('GET', 'k').and_return('[[9,1.5]]')
      ran = false
      expect(Cache.fetch('k', ttl: 60) { ran = true; [] }).to eq([[9, 1.5]])
      expect(ran).to be false
    end

    it 'Redis error on GET → computes fresh (never breaks the caller)' do
      allow(fake).to receive(:call).with('GET', 'k').and_raise(RuntimeError, 'connection refused')
      allow(fake).to receive(:call) # tolerate the SET attempt
      expect(Cache.fetch('k', ttl: 60) { [42] }).to eq([42])
    end

    it 'corrupt cached JSON → recomputes' do
      allow(fake).to receive(:call).with('GET', 'k').and_return('not json{')
      allow(fake).to receive(:call) # SET
      expect(Cache.fetch('k', ttl: 60) { [7] }).to eq([7])
    end

    it 'SET failure is swallowed — still returns the computed value' do
      allow(fake).to receive(:call).with('GET', 'k').and_return(nil)
      allow(fake).to receive(:call).with('SET', any_args).and_raise('redis down')
      expect(Cache.fetch('k', ttl: 60) { [5] }).to eq([5])
    end
  end

  it 'is bypassed in the test env by default (enabled? is false)' do
    allow(Cache).to receive(:enabled?).and_call_original
    # No client interaction at all when disabled.
    expect(Cache).not_to receive(:client)
    expect(Cache.fetch('k', ttl: 60) { :computed }).to eq(:computed)
  end
end
