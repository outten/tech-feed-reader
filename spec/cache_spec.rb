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

    context 'marshal: true (for symbol-keyed / mixed-key Ruby structures)' do
      let(:value) { [{ term: 'ruby', count: 3, articles: [{ 'uid' => 'x' }] }] }

      it 'miss → Marshal-dumps the value and returns it' do
        allow(fake).to receive(:call).with('GET', 'k').and_return(nil)
        expect(fake).to receive(:call).with('SET', 'k', Marshal.dump(value), 'EX', 60)
        expect(Cache.fetch('k', ttl: 60, marshal: true) { value }).to eq(value)
      end

      it 'hit → unmarshals with symbol AND inner string keys intact' do
        allow(fake).to receive(:call).with('GET', 'k').and_return(Marshal.dump(value))
        result = Cache.fetch('k', ttl: 60, marshal: true) { raise 'should not recompute' }
        expect(result.first[:term]).to eq('ruby')               # symbol key
        expect(result.first[:articles].first['uid']).to eq('x') # inner string key
      end

      it 'corrupt marshal payload → recomputes' do
        allow(fake).to receive(:call).with('GET', 'k').and_return('not marshal data')
        allow(fake).to receive(:call) # SET
        expect(Cache.fetch('k', ttl: 60, marshal: true) { value }).to eq(value)
      end
    end
  end

  it 'is bypassed in the test env by default (enabled? is false)' do
    allow(Cache).to receive(:enabled?).and_call_original
    # No client interaction at all when disabled.
    expect(Cache).not_to receive(:client)
    expect(Cache.fetch('k', ttl: 60) { :computed }).to eq(:computed)
  end

  describe '.write (force-refresh for cache warming)' do
    it 'unconditionally SETs the value with TTL and returns it' do
      expect(fake).to receive(:call).with('SET', 'k', '[1,2]', 'EX', 60)
      expect(Cache.write('k', [1, 2], ttl: 60)).to eq([1, 2])
    end

    it 'is a no-op that still returns the value when caching is disabled' do
      allow(Cache).to receive(:enabled?).and_call_original
      expect(Cache).not_to receive(:client)
      expect(Cache.write('k', [9], ttl: 60)).to eq([9])
    end
  end
end
