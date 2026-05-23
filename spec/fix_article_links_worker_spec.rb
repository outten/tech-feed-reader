require_relative 'spec_helper'
require_relative '../app/workers/fix_article_links_worker'

RSpec.describe FixArticleLinksWorker do
  describe '#perform' do
    it 'delegates to ArticleLinkScrubber.run! and logs a completion summary' do
      result = {
        scanned: 3, changed: 1, unchanged: 1, skipped: 1,
        empty_marked: 0, remaining: 0
      }
      expect(ArticleLinkScrubber).to receive(:run!).and_return(result)
      expect(AppLogger).to receive(:info).with('fix_article_links_complete', hash_including(changed: 1))

      FixArticleLinksWorker.new.perform
    end
  end

  describe 'Sidekiq integration' do
    it 'is a Sidekiq::Worker on the default queue with capped retries' do
      expect(FixArticleLinksWorker.included_modules).to include(Sidekiq::Worker)
      expect(FixArticleLinksWorker.sidekiq_options['queue'].to_s).to eq('default')
      expect(FixArticleLinksWorker.sidekiq_options['retry']).to eq(2)
    end
  end
end
