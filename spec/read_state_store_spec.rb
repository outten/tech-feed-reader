require_relative 'spec_helper'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/read_state_store'

RSpec.describe ReadStateStore do
  let!(:feed) { FeedsStore.add(url: 'https://example.com/feed.rss') }
  let!(:article_id) do
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: 'a' * 12, title: 'One',
      url: 'https://example.com/1', author: nil,
      published_at: '2026-05-02T12:00:00Z',
      content_html: '<p>x</p>', content_text: 'x'
    }])
    ArticlesStore.find_by_uid('a' * 12)['id']
  end

  describe '.get' do
    it 'returns synthetic defaults when no row exists' do
      state = ReadStateStore.get(article_id)
      expect(state['read']).to       eq(0)
      expect(state['bookmarked']).to eq(0)
      expect(state['archived']).to   eq(0)
      expect(state['opened_at']).to  be_nil
    end

    it 'returns the stored row once one exists' do
      ReadStateStore.mark_read(article_id)
      state = ReadStateStore.get(article_id)
      expect(state['read']).to eq(1)
    end
  end

  describe '.opened!' do
    it 'sets read=1 and opened_at to a timestamp' do
      state = ReadStateStore.opened!(article_id)
      expect(state['read']).to eq(1)
      expect(state['opened_at']).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
    end

    it 'preserves bookmarked / archived flags' do
      ReadStateStore.mark_bookmarked(article_id)
      ReadStateStore.opened!(article_id)
      state = ReadStateStore.get(article_id)
      expect(state['bookmarked']).to eq(1)
    end
  end

  describe 'toggle methods' do
    it 'mark_read flips between 0 and 1 idempotently' do
      ReadStateStore.mark_read(article_id, read: true)
      expect(ReadStateStore.get(article_id)['read']).to eq(1)
      ReadStateStore.mark_read(article_id, read: false)
      expect(ReadStateStore.get(article_id)['read']).to eq(0)
      ReadStateStore.mark_read(article_id, read: false)
      expect(ReadStateStore.get(article_id)['read']).to eq(0)
    end

    it 'mark_bookmarked is independent of read' do
      ReadStateStore.mark_read(article_id)
      ReadStateStore.mark_bookmarked(article_id)
      state = ReadStateStore.get(article_id)
      expect(state['read']).to       eq(1)
      expect(state['bookmarked']).to eq(1)
    end

    it 'mark_archived is independent of read and bookmarked' do
      ReadStateStore.mark_bookmarked(article_id)
      ReadStateStore.mark_archived(article_id)
      state = ReadStateStore.get(article_id)
      expect(state['bookmarked']).to eq(1)
      expect(state['archived']).to   eq(1)
    end
  end

  describe '.unread_count' do
    it 'counts articles with no read_state row OR read=0' do
      ArticlesStore.import(feed_id: feed['id'], entries: [{
        uid: 'b' * 12, title: 'Two',
        url: 'https://example.com/2', author: nil,
        published_at: '2026-05-01T12:00:00Z',
        content_html: '<p>y</p>', content_text: 'y'
      }])

      expect(ReadStateStore.unread_count).to eq(2)
      ReadStateStore.mark_read(article_id)
      expect(ReadStateStore.unread_count).to eq(1)
    end
  end

  describe '.bookmarked_count' do
    it 'counts only bookmarked rows' do
      expect(ReadStateStore.bookmarked_count).to eq(0)
      ReadStateStore.mark_bookmarked(article_id)
      expect(ReadStateStore.bookmarked_count).to eq(1)
      ReadStateStore.mark_bookmarked(article_id, value: false)
      expect(ReadStateStore.bookmarked_count).to eq(0)
    end
  end

  describe 'cascade behaviour' do
    it 'is removed when its article is deleted' do
      ReadStateStore.mark_read(article_id)
      Database.connection.execute('DELETE FROM articles WHERE id = ?', [article_id])
      remaining = Database.connection.execute('SELECT COUNT(*) AS c FROM read_state').first['c']
      expect(remaining).to eq(0)
    end
  end
end
