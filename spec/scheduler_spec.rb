require_relative 'spec_helper'
require_relative '../app/scheduler'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'

RSpec.describe Scheduler do
  describe '.due?' do
    let(:now) { Time.parse('2026-05-02T12:00:00Z') }

    it 'returns true when last_fetched_at is empty / nil' do
      expect(Scheduler.due?({ 'last_fetched_at' => nil,  'fetch_interval_seconds' => 3600 }, now: now)).to be(true)
      expect(Scheduler.due?({ 'last_fetched_at' => '',   'fetch_interval_seconds' => 3600 }, now: now)).to be(true)
    end

    it 'returns true when last_fetched_at is unparseable' do
      feed = { 'last_fetched_at' => 'not-a-date', 'fetch_interval_seconds' => 3600 }
      expect(Scheduler.due?(feed, now: now)).to be(true)
    end

    it 'returns false when the next-fetch deadline is in the future' do
      feed = {
        'last_fetched_at'        => '2026-05-02T11:30:00Z', # 30 min ago
        'fetch_interval_seconds' => 3600                    # interval 1h → due in 30 min
      }
      expect(Scheduler.due?(feed, now: now)).to be(false)
    end

    it 'returns true once the interval has elapsed' do
      feed = {
        'last_fetched_at'        => '2026-05-02T10:30:00Z', # 90 min ago
        'fetch_interval_seconds' => 3600                    # interval 1h → due 30 min ago
      }
      expect(Scheduler.due?(feed, now: now)).to be(true)
    end
  end

  describe '.due_feeds' do
    it 'filters a list to only the due rows' do
      now   = Time.parse('2026-05-02T12:00:00Z')
      feeds = [
        { 'id' => 1, 'last_fetched_at' => nil,                    'fetch_interval_seconds' => 3600 },
        { 'id' => 2, 'last_fetched_at' => '2026-05-02T11:55:00Z', 'fetch_interval_seconds' => 3600 },
        { 'id' => 3, 'last_fetched_at' => '2026-05-02T10:00:00Z', 'fetch_interval_seconds' => 3600 }
      ]
      due = Scheduler.due_feeds(feeds, now: now).map { |f| f['id'] }
      expect(due).to contain_exactly(1, 3)
    end
  end

  describe '.refresh_one' do
    let(:feed)    { FeedsStore.add(url: 'https://example.com/feed.rss') }
    let(:rss_body) { File.read(File.expand_path('fixtures/rss20.xml', __dir__)) }

    def stub_http(code:, body: '', headers: {})
      response = instance_double(Net::HTTPResponse, code: code.to_s, body: body)
      allow(response).to receive(:[]) { |k| headers[k] }
      allow(Providers::HttpClient).to receive(:get).and_return(response)
    end

    it 'returns [result, imported_count] on success' do
      stub_http(code: 200, body: rss_body)
      result, imported = Scheduler.refresh_one(feed)
      expect(result.status).to eq(:ok)
      expect(imported).to eq(2)
      expect(ArticlesStore.count).to eq(2)
    end

    it 'returns 0 imported on a 304' do
      stub_http(code: 304, body: '')
      result, imported = Scheduler.refresh_one(feed)
      expect(result.status).to eq(:not_modified)
      expect(imported).to eq(0)
    end

    it 'returns 0 imported on transport error' do
      allow(Providers::HttpClient).to receive(:get).and_raise(Net::ReadTimeout)
      result, imported = Scheduler.refresh_one(feed)
      expect(result.status).to eq(:error)
      expect(imported).to eq(0)
    end
  end
end
