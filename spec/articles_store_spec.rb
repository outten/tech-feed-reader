require_relative 'spec_helper'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'

RSpec.describe ArticlesStore do
  let!(:feed) { FeedsStore.add(url: 'https://example.com/feed.rss') }

  def entry(uid:, title:, content_text: '', published_at: '2026-05-02T12:00:00Z')
    {
      uid:          uid,
      title:        title,
      url:          "https://example.com/#{uid}",
      author:       'Author',
      published_at: published_at,
      content_html: "<p>#{content_text}</p>",
      content_text: content_text
    }
  end

  describe '.import' do
    it 'inserts new entries and returns the new-row count' do
      n = ArticlesStore.import(feed_id: feed['id'], entries: [
        entry(uid: 'a' * 12, title: 'One'),
        entry(uid: 'b' * 12, title: 'Two')
      ])
      expect(n).to eq(2)
      expect(ArticlesStore.count).to eq(2)
    end

    it 'skips uids that already exist (idempotent re-import)' do
      ArticlesStore.import(feed_id: feed['id'], entries: [entry(uid: 'a' * 12, title: 'One')])
      n = ArticlesStore.import(feed_id: feed['id'], entries: [
        entry(uid: 'a' * 12, title: 'One again'),
        entry(uid: 'c' * 12, title: 'Three')
      ])
      expect(n).to eq(1)
      expect(ArticlesStore.count).to eq(2)

      # The original row is untouched — title isn't overwritten.
      expect(ArticlesStore.find_by_uid('a' * 12)['title']).to eq('One')
    end

    it 'returns 0 on an empty batch without opening a transaction' do
      expect(ArticlesStore.import(feed_id: feed['id'], entries: [])).to eq(0)
    end
  end

  describe '.find / .find_by_uid' do
    before do
      ArticlesStore.import(feed_id: feed['id'], entries: [entry(uid: 'a' * 12, title: 'Hello')])
    end

    it 'returns nil for unknown id / uid' do
      expect(ArticlesStore.find(999)).to be_nil
      expect(ArticlesStore.find_by_uid('z' * 12)).to be_nil
    end

    it 'returns the row for known id / uid' do
      row = ArticlesStore.find_by_uid('a' * 12)
      expect(row['title']).to eq('Hello')
      expect(ArticlesStore.find(row['id'])['uid']).to eq('a' * 12)
    end
  end

  describe '.recent and .for_feed' do
    before do
      ArticlesStore.import(feed_id: feed['id'], entries: [
        entry(uid: 'a' * 12, title: 'Old',    published_at: '2026-04-01T00:00:00Z'),
        entry(uid: 'b' * 12, title: 'Newer',  published_at: '2026-05-01T00:00:00Z'),
        entry(uid: 'c' * 12, title: 'Newest', published_at: '2026-06-01T00:00:00Z')
      ])
    end

    it 'orders recent by published_at DESC' do
      titles = ArticlesStore.recent(limit: 10).map { |a| a['title'] }
      expect(titles).to eq(%w[Newest Newer Old])
    end

    it 'paginates via limit / offset' do
      page1 = ArticlesStore.recent(limit: 2, offset: 0).map { |a| a['title'] }
      page2 = ArticlesStore.recent(limit: 2, offset: 2).map { |a| a['title'] }
      expect(page1).to eq(%w[Newest Newer])
      expect(page2).to eq(%w[Old])
    end

    it 'scopes for_feed to a single feed' do
      other = FeedsStore.add(url: 'https://other.example.com/feed')
      ArticlesStore.import(feed_id: other['id'], entries: [entry(uid: 'd' * 12, title: 'Other')])

      mine_titles  = ArticlesStore.for_feed(feed['id']).map  { |a| a['title'] }
      other_titles = ArticlesStore.for_feed(other['id']).map { |a| a['title'] }
      expect(mine_titles).to contain_exactly('Old', 'Newer', 'Newest')
      expect(other_titles).to eq(['Other'])
    end
  end

  describe '.search' do
    before do
      ArticlesStore.import(feed_id: feed['id'], entries: [
        entry(uid: 'a' * 12, title: 'Ruby on Rails',  content_text: 'A web framework written in Ruby.'),
        entry(uid: 'b' * 12, title: 'JavaScript fun', content_text: 'A scripting language for browsers.'),
        entry(uid: 'c' * 12, title: 'Database tips',  content_text: 'Indexes, queries, and Ruby ORM patterns.')
      ])
    end

    it 'returns matches via the FTS5 virtual table' do
      titles = ArticlesStore.search('ruby').map { |a| a['title'] }
      expect(titles).to contain_exactly('Ruby on Rails', 'Database tips')
    end

    it 'returns an empty array for blank queries (no FTS5 syntax error)' do
      expect(ArticlesStore.search('')).to eq([])
      expect(ArticlesStore.search('   ')).to eq([])
    end

    it 'honours the limit' do
      results = ArticlesStore.search('ruby', limit: 1)
      expect(results.length).to eq(1)
    end
  end
end
