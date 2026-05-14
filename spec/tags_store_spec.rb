require_relative 'spec_helper'
require_relative '../app/tags_store'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'

RSpec.describe TagsStore do
  describe '.add' do
    it 'inserts a tag rule and returns the row' do
      tag = TagsStore.add(user_id: 1, name: 'ruby', match_kind: 'keyword', match_value: 'ruby')
      expect(tag['id']).to be > 0
      expect(tag['name']).to eq('ruby')
      expect(tag['match_kind']).to eq('keyword')
      expect(tag['match_value']).to eq('ruby')
    end

    it 'rejects duplicate names via UNIQUE' do
      TagsStore.add(user_id: 1, name: 'ruby', match_kind: 'keyword', match_value: 'ruby')
      expect {
        TagsStore.add(user_id: 1, name: 'ruby', match_kind: 'keyword', match_value: 'rails')
      }.to raise_error(SQLite3::ConstraintException, /UNIQUE/)
    end

    it 'rejects unknown match_kind via the schema CHECK' do
      expect {
        TagsStore.add(user_id: 1, name: 'x', match_kind: 'bogus', match_value: 'x')
      }.to raise_error(SQLite3::ConstraintException, /CHECK/)
    end
  end

  describe '.find / .find_by_name / .all' do
    before do
      TagsStore.add(user_id: 1, name: 'rails', match_kind: 'keyword', match_value: 'rails')
      TagsStore.add(user_id: 1, name: 'ai',    match_kind: 'keyword', match_value: 'ai')
    end

    it '.all returns rows sorted by name' do
      expect(TagsStore.all(1).map { |t| t['name'] }).to eq(%w[ai rails])
    end

    it '.find_by_name lookup' do
      expect(TagsStore.find_by_name(1, 'rails')).not_to be_nil
      expect(TagsStore.find_by_name(1, 'nope')).to be_nil
    end

    it '.find by id' do
      id = TagsStore.find_by_name(1, 'ai')['id']
      expect(TagsStore.find(1, id)['name']).to eq('ai')
    end
  end

  describe '.remove' do
    it 'cascades to article_tags' do
      tag  = TagsStore.add(user_id: 1, name: 'ruby', match_kind: 'keyword', match_value: 'ruby')
      feed = FeedsStore.add(url: 'https://example.com/feed.rss')
      ArticlesStore.import(feed_id: feed['id'], entries: [{
        uid: 'a' * 12, title: 'Ruby Stuff',
        url: 'https://example.com/r', author: nil,
        published_at: '2026-05-02T12:00:00Z',
        content_html: '<p>x</p>', content_text: 'ruby is great'
      }])
      article_id = ArticlesStore.find_by_uid('a' * 12)['id']

      # auto-applied via the import path
      expect(TagsStore.tags_for_article(1, article_id).map { |t| t['name'] }).to include('ruby')

      TagsStore.remove(1, tag['id'])
      expect(TagsStore.tags_for_article(1, article_id)).to be_empty
    end
  end

  describe '.tags_for_articles bulk lookup' do
    it 'returns a hash keyed by article_id' do
      feed = FeedsStore.add(url: 'https://example.com/feed.rss')
      tag1 = TagsStore.add(user_id: 1, name: 'tag1', match_kind: 'feed_id', match_value: feed['id'].to_s)
      tag2 = TagsStore.add(user_id: 1, name: 'tag2', match_kind: 'feed_id', match_value: feed['id'].to_s)
      ArticlesStore.import(feed_id: feed['id'], entries: [{
        uid: 'a' * 12, title: 'A', url: 'https://example.com/a', author: nil,
        published_at: '2026-05-02T12:00:00Z', content_html: '<p>x</p>', content_text: 'x'
      }])
      article_id = ArticlesStore.find_by_uid('a' * 12)['id']

      result = TagsStore.tags_for_articles(1, [article_id])
      expect(result[article_id].map { |r| r['name'] }).to contain_exactly('tag1', 'tag2')
    end

    it 'returns {} for an empty input list' do
      expect(TagsStore.tags_for_articles(1, [])).to eq({})
    end
  end
end
