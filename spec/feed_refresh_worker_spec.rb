require_relative 'spec_helper'
require_relative '../app/workers/feed_refresh_worker'
require_relative '../app/feeds_store'
require_relative '../app/scheduler'

RSpec.describe FeedRefreshWorker do
  describe '#perform' do
    it 'looks up the feed and hands it off to Scheduler.refresh_one' do
      feed = FeedsStore.add(url: 'https://example.com/feed.rss', title: 'Example')
      result = double('Result', status: :ok, entries: [])
      expect(Scheduler).to receive(:refresh_one) do |arg|
        expect(arg['id']).to eq(feed['id'])
        [result, 0]
      end

      FeedRefreshWorker.new.perform(feed['id'])
    end

    it 'no-ops when the feed has been deleted between enqueue and run' do
      expect(Scheduler).not_to receive(:refresh_one)
      expect { FeedRefreshWorker.new.perform(99_999) }.not_to raise_error
    end

    it 'coerces a string feed_id (Sidekiq serialises args through JSON)' do
      feed = FeedsStore.add(url: 'https://example.com/feed.rss', title: 'Example')
      expect(Scheduler).to receive(:refresh_one) do |arg|
        expect(arg['id']).to eq(feed['id'])
        [double(status: :ok, entries: []), 0]
      end
      FeedRefreshWorker.new.perform(feed['id'].to_s)
    end
  end

  describe 'Sidekiq integration' do
    it 'is a Sidekiq::Worker on the default queue' do
      expect(FeedRefreshWorker.included_modules).to include(Sidekiq::Worker)
      expect(FeedRefreshWorker.sidekiq_options['queue'].to_s).to eq('default')
    end
  end
end
