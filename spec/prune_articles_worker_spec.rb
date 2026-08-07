require_relative 'spec_helper'
require_relative '../app/workers/prune_articles_worker'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/read_state_store'

RSpec.describe PruneArticlesWorker do
  let(:feed) { FeedsStore.add(url: 'https://x.com/rss', title: 'Example') }

  def add(uid:, days_ago:)
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: uid, title: uid,
      url: "https://x.com/#{uid}", author: nil,
      published_at: (Time.now - days_ago * 86_400).iso8601,
      content_html: '<p>x</p>', content_text: 'x',
      audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
    }])
    ArticlesStore.find_by_uid(uid)
  end

  describe '#perform' do
    it 'deletes non-bookmarked articles past the retention window, read or unread' do
      old_read      = add(uid: 'oldreadthis1', days_ago: 45)
      old_unread    = add(uid: 'oldunreadone', days_ago: 45)
      old_bookmark  = add(uid: 'oldbookmark1', days_ago: 45)
      recent        = add(uid: 'recentonenow', days_ago: 1)

      ReadStateStore.mark_read(1, old_read['id'], read: true)
      ReadStateStore.mark_bookmarked(1, old_bookmark['id'], value: true)

      PruneArticlesWorker.new.perform

      expect(ArticlesStore.find_by_uid('oldreadthis1')).to be_nil
      expect(ArticlesStore.find_by_uid('oldunreadone')).to be_nil
      expect(ArticlesStore.find_by_uid('oldbookmark1')).not_to be_nil
      expect(ArticlesStore.find_by_uid('recentonenow')).not_to be_nil
    end

    it 'always calls Pruner.prune_old with keep_unread: false, regardless of ENV' do
      expect(Pruner).to receive(:prune_old).with(hash_including(keep_unread: false))
      PruneArticlesWorker.new.perform
    end
  end

  describe 'Sidekiq integration' do
    it 'is a Sidekiq::Worker on the default queue with capped retries' do
      expect(PruneArticlesWorker.included_modules).to include(Sidekiq::Worker)
      expect(PruneArticlesWorker.sidekiq_options['queue'].to_s).to eq('default')
      expect(PruneArticlesWorker.sidekiq_options['retry']).to eq(2)
    end
  end
end
