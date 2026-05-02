require_relative 'spec_helper'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/summary_store'

RSpec.describe SummaryStore do
  let!(:feed) { FeedsStore.add(url: 'https://example.com/feed.rss') }
  let!(:article_id) do
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: 'a' * 12, title: 'A', url: 'https://example.com/a', author: nil,
      published_at: '2026-05-02T12:00:00Z',
      content_html: '<p>x</p>', content_text: 'x is fine'
    }])
    ArticlesStore.find_by_uid('a' * 12)['id']
  end

  describe '.upsert' do
    it 'inserts an extractive-only row' do
      row = SummaryStore.upsert(article_id, extractive: 'Hello world.')
      expect(row['extractive']).to eq('Hello world.')
      expect(row['llm']).to be_nil
    end

    it 'merges fields without clobbering on a second upsert' do
      SummaryStore.upsert(article_id, extractive: 'First version.')
      SummaryStore.upsert(article_id, llm: 'LLM version.', llm_model: 'claude-opus-4-7')

      row = SummaryStore.find(article_id)
      expect(row['extractive']).to eq('First version.')
      expect(row['llm']).to eq('LLM version.')
      expect(row['llm_model']).to eq('claude-opus-4-7')
    end

    it 'replaces a field when explicitly passed' do
      SummaryStore.upsert(article_id, extractive: 'Old.')
      SummaryStore.upsert(article_id, extractive: 'New.')
      expect(SummaryStore.find(article_id)['extractive']).to eq('New.')
    end
  end

  describe '.find / .has_extractive?' do
    it 'returns nil for unknown article_id' do
      expect(SummaryStore.find(999)).to be_nil
      expect(SummaryStore.has_extractive?(999)).to be(false)
    end

    it 'reports has_extractive? based on stored content' do
      # Import auto-generates a summary; delete to test the false branch.
      SummaryStore.remove(article_id)
      expect(SummaryStore.has_extractive?(article_id)).to be(false)
      SummaryStore.upsert(article_id, extractive: 'Some summary.')
      expect(SummaryStore.has_extractive?(article_id)).to be(true)
    end
  end

  describe 'cascade behaviour' do
    it 'is removed when its article is deleted' do
      SummaryStore.upsert(article_id, extractive: 'Hi.')
      Database.connection.execute('DELETE FROM articles WHERE id = ?', [article_id])
      expect(Database.connection.execute('SELECT COUNT(*) AS c FROM summaries').first['c']).to eq(0)
    end
  end
end
