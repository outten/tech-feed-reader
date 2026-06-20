require_relative 'spec_helper'
require_relative '../app/notifier'

RSpec.describe Notifier do
  around do |ex|
    old = ENV['NTFY_URL']
    ex.run
    old.nil? ? ENV.delete('NTFY_URL') : ENV['NTFY_URL'] = old
  end

  describe '.push' do
    it 'no-ops and returns false when NTFY_URL is unset' do
      ENV.delete('NTFY_URL')
      expect(Notifier).not_to receive(:post)
      expect(Notifier.push(title: 't', body: 'b')).to eq(false)
    end

    it 'posts and returns true when NTFY_URL is set' do
      ENV['NTFY_URL'] = 'https://ntfy.example/topic'
      allow(Notifier).to receive(:deduped?).and_return(false)
      expect(Notifier).to receive(:post).with('https://ntfy.example/topic', 't', 'b', ['x'], 'high')
      expect(Notifier.push(title: 't', body: 'b', tags: ['x'], priority: 'high')).to eq(true)
    end

    it 'swallows a transport error and returns false (never raises into the caller)' do
      ENV['NTFY_URL'] = 'https://ntfy.example/topic'
      allow(Notifier).to receive(:deduped?).and_return(false)
      allow(Notifier).to receive(:post).and_raise(SocketError, 'boom')
      result = nil
      expect { result = Notifier.push(title: 't', body: 'b') }.not_to raise_error
      expect(result).to eq(false)
    end

    it 'does not post when the alert is deduped' do
      ENV['NTFY_URL'] = 'https://ntfy.example/topic'
      allow(Notifier).to receive(:deduped?).and_return(true)
      expect(Notifier).not_to receive(:post)
      expect(Notifier.push(title: 't', body: 'b', dedupe_key: 'k')).to eq(false)
    end
  end

  describe '.deduped?' do
    it 'is false for a nil/empty key (no rate-limiting requested)' do
      expect(Notifier.deduped?(nil, 900)).to eq(false)
      expect(Notifier.deduped?('', 900)).to eq(false)
    end

    it 'is false on first SET NX, true on a repeat within the window' do
      fake = double('redis')
      allow(Cache).to receive(:client).and_return(fake)
      # SET ... NX returns 'OK' when it set the key (first time) → not deduped;
      # nil when the key already existed → deduped.
      allow(fake).to receive(:call).and_return('OK', nil)
      expect(Notifier.deduped?('k', 900)).to eq(false)
      expect(Notifier.deduped?('k', 900)).to eq(true)
    end

    it 'fails open (not deduped) when Redis errors' do
      allow(Cache).to receive(:client).and_raise(StandardError, 'redis down')
      expect(Notifier.deduped?('k', 900)).to eq(false)
    end
  end
end
