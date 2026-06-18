require_relative 'spec_helper'
require_relative '../app/workers/foryou_cache_warm_worker'

# Cache-warming worker for the For-You ranking (change: speed-up-article-load).
# Cache itself is disabled in the test env, so these assert the worker's
# behaviour (who it warms, with what params) rather than Redis state.
RSpec.describe ForYouCacheWarmWorker do
  describe 'UsersStore.active_since' do
    it 'returns users seen since the cutoff and excludes older / never-seen ones' do
      UsersStore.touch_last_seen!(1)
      hour_ago = (Time.now.utc - 3600).strftime('%Y-%m-%d %H:%M:%S')
      expect(UsersStore.active_since(hour_ago)).to include(1)

      hour_ahead = (Time.now.utc + 3600).strftime('%Y-%m-%d %H:%M:%S')
      expect(UsersStore.active_since(hour_ahead)).not_to include(1)
    end
  end

  describe '#perform' do
    it 'force-warms the ranking for each active user across both warm states' do
      UsersStore.touch_last_seen!(1)
      ForYouCacheWarmWorker::WARM_STATES.each do |state|
        expect(Recommendation::ForYou).to receive(:ranked_ids)
          .with(1, hash_including(state: state, kind: :all, topic: nil, force: true))
      end
      ForYouCacheWarmWorker.new.perform
    end

    it 'no-ops cleanly when no user is active (never-seen users are excluded)' do
      # The seeded test user has a NULL last_seen_at, so nobody is active.
      expect(Recommendation::ForYou).not_to receive(:ranked_ids)
      expect { ForYouCacheWarmWorker.new.perform }.not_to raise_error
    end
  end
end
