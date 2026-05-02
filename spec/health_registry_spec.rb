require_relative 'spec_helper'
require 'net/http'
require_relative '../app/health_registry'

RSpec.describe HealthRegistry do
  # The registry is a no-op in test env unless HEALTH_REGISTRY=1.
  # Each example flips the flag on, runs, then resets so unrelated
  # specs don't see leaked state.
  around(:each) do |ex|
    ENV['HEALTH_REGISTRY'] = '1'
    HealthRegistry.reset!
    ex.run
  ensure
    ENV.delete('HEALTH_REGISTRY')
    HealthRegistry.reset!
  end

  describe '.measure' do
    it 'records latency + status from a Result-like return value' do
      result = Struct.new(:status).new(:ok)
      out    = HealthRegistry.measure(1) { result }
      expect(out).to eq(result)

      obs = HealthRegistry.observations
      expect(obs.length).to eq(1)
      expect(obs.first.feed_id).to eq(1)
      expect(obs.first.status).to eq(:ok)
      expect(obs.first.latency_ms).to be >= 0
    end

    it 're-raises exceptions but still records :error' do
      expect {
        HealthRegistry.measure(7) { raise Net::ReadTimeout }
      }.to raise_error(Net::ReadTimeout)

      obs = HealthRegistry.observations.last
      expect(obs.feed_id).to eq(7)
      expect(obs.status).to  eq(:error)
      expect(obs.note).to    eq('Net::ReadTimeout')
    end

    it 'is a no-op when HEALTH_REGISTRY is unset' do
      ENV.delete('HEALTH_REGISTRY')
      out = HealthRegistry.measure(1) { :sentinel }
      expect(out).to eq(:sentinel)
      expect(HealthRegistry.observations).to be_empty
    end
  end

  describe '.record' do
    it 'appends an observation' do
      HealthRegistry.record(feed_id: 2, status: :not_modified, latency_ms: 42)
      obs = HealthRegistry.observations.first
      expect(obs.feed_id).to eq(2)
      expect(obs.status).to eq(:not_modified)
      expect(obs.latency_ms).to eq(42)
      expect(obs.at).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
    end

    it 'enforces the CAPACITY ring-buffer cap' do
      (HealthRegistry::CAPACITY + 50).times do |i|
        HealthRegistry.record(feed_id: 1, status: :ok, latency_ms: i)
      end
      expect(HealthRegistry.observations.length).to eq(HealthRegistry::CAPACITY)
      expect(HealthRegistry.observations.first.latency_ms).to eq(50) # oldest 50 dropped
    end
  end

  describe '.observations_for' do
    it 'filters to a single feed' do
      HealthRegistry.record(feed_id: 1, status: :ok, latency_ms: 10)
      HealthRegistry.record(feed_id: 2, status: :ok, latency_ms: 20)
      HealthRegistry.record(feed_id: 1, status: :error, latency_ms: 30)
      expect(HealthRegistry.observations_for(1).map(&:status)).to eq(%i[ok error])
    end
  end

  describe '.per_feed_summary' do
    before do
      HealthRegistry.record(feed_id: 1, status: :ok,           latency_ms: 100)
      HealthRegistry.record(feed_id: 1, status: :ok,           latency_ms: 300)
      HealthRegistry.record(feed_id: 1, status: :error,        latency_ms: 500)
      HealthRegistry.record(feed_id: 2, status: :not_modified, latency_ms: 50)
    end

    it 'aggregates totals + average successful latency per feed' do
      summary = HealthRegistry.per_feed_summary
      expect(summary[1][:total]).to eq(3)
      expect(summary[1][:success]).to eq(2)
      expect(summary[1][:errors]).to eq(1)
      expect(summary[1][:avg_latency_ms]).to eq(200) # mean of 100 + 300

      expect(summary[2][:errors]).to eq(0)
      expect(summary[2][:avg_latency_ms]).to eq(50)
    end
  end

  describe '.degraded?' do
    it 'returns false when there are too few observations to judge' do
      4.times { HealthRegistry.record(feed_id: 1, status: :error, latency_ms: 0) }
      expect(HealthRegistry.degraded?).to be(false)
    end

    it 'returns true when the recent window is mostly errors' do
      DEGRADED_WINDOW = HealthRegistry::DEGRADED_WINDOW
      DEGRADED_WINDOW.times { HealthRegistry.record(feed_id: 1, status: :error, latency_ms: 0) }
      expect(HealthRegistry.degraded?).to be(true)
    end

    it 'returns false when most recent observations are successful' do
      HealthRegistry::DEGRADED_WINDOW.times { HealthRegistry.record(feed_id: 1, status: :ok, latency_ms: 1) }
      expect(HealthRegistry.degraded?).to be(false)
    end

    it 'only considers the most recent DEGRADED_WINDOW observations' do
      30.times { HealthRegistry.record(feed_id: 1, status: :error, latency_ms: 0) }
      HealthRegistry::DEGRADED_WINDOW.times { HealthRegistry.record(feed_id: 1, status: :ok, latency_ms: 1) }
      expect(HealthRegistry.degraded?).to be(false)
    end
  end
end
