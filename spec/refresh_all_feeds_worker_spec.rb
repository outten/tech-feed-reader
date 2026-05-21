require_relative 'spec_helper'
require_relative '../app/workers/refresh_all_feeds_worker'
require_relative '../app/feeds_store'

RSpec.describe RefreshAllFeedsWorker do
  describe '#perform' do
    it 'enqueues one FeedRefreshWorker per feed' do
      FeedsStore.add(url: 'https://a.example.com/feed.rss', title: 'A')
      FeedsStore.add(url: 'https://b.example.com/feed.rss', title: 'B')

      enqueued = []
      allow(FeedRefreshWorker).to receive(:perform_async) { |id| enqueued << id }

      RefreshAllFeedsWorker.new.perform

      expected_ids = FeedsStore.all.map { |f| f['id'] }
      expect(enqueued.sort).to eq(expected_ids.sort)
    end

    it 'is a no-op when there are no feeds (does not enqueue anything)' do
      expect(FeedsStore.all).to be_empty
      expect(FeedRefreshWorker).not_to receive(:perform_async)
      expect { RefreshAllFeedsWorker.new.perform }.not_to raise_error
    end
  end

  describe 'Sidekiq integration' do
    it 'is a Sidekiq::Worker on the default queue with capped retries' do
      expect(RefreshAllFeedsWorker.included_modules).to include(Sidekiq::Worker)
      expect(RefreshAllFeedsWorker.sidekiq_options['queue'].to_s).to eq('default')
      expect(RefreshAllFeedsWorker.sidekiq_options['retry']).to eq(2)
    end
  end
end
