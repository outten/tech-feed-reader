require_relative 'spec_helper'
require_relative '../app/workers/sports_sync_worker'

RSpec.describe SportsSyncWorker do
  describe '#perform' do
    it 'delegates to SportsSync.run! and logs a completion summary' do
      result = {
        matches_upserted: 3,
        matches_total:    12,
        standings_total:  20,
        tennis_total:     300,
        tennis_ranked:    150
      }
      expect(SportsSync).to receive(:run!).and_return(result)
      expect(AppLogger).to receive(:info).with('sports_sync_complete', hash_including(matches_upserted: 3))

      SportsSyncWorker.new.perform
    end
  end

  describe 'Sidekiq integration' do
    it 'is a Sidekiq::Worker on the default queue with capped retries' do
      expect(SportsSyncWorker.included_modules).to include(Sidekiq::Worker)
      expect(SportsSyncWorker.sidekiq_options['queue'].to_s).to eq('default')
      expect(SportsSyncWorker.sidekiq_options['retry']).to eq(2)
    end
  end
end
