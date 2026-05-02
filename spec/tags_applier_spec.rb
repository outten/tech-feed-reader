require_relative 'spec_helper'
require_relative '../app/tags_applier'
require_relative '../app/tags_store'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'

RSpec.describe TagsApplier do
  describe '.matches?' do
    it 'matches keyword case-insensitively in title or content_text' do
      rule = { 'match_kind' => 'keyword', 'match_value' => 'rust' }
      expect(TagsApplier.matches?({ 'title' => 'A Rust Story', 'content_text' => '' }, rule)).to be(true)
      expect(TagsApplier.matches?({ 'title' => 'Other', 'content_text' => 'rust here' }, rule)).to be(true)
      expect(TagsApplier.matches?({ 'title' => 'Other', 'content_text' => 'go is fast' }, rule)).to be(false)
    end

    it 'matches regex against title or content_text (case-insensitive)' do
      rule = { 'match_kind' => 'regex', 'match_value' => '\\bruby\\b' }
      expect(TagsApplier.matches?({ 'title' => 'About Ruby', 'content_text' => '' }, rule)).to be(true)
      expect(TagsApplier.matches?({ 'title' => 'rubyist', 'content_text' => '' }, rule)).to be(false) # \b boundary
    end

    it 'matches feed_id by exact match (string in match_value, integer in article)' do
      rule = { 'match_kind' => 'feed_id', 'match_value' => '7' }
      expect(TagsApplier.matches?({ 'feed_id' => 7 }, rule)).to be(true)
      expect(TagsApplier.matches?({ 'feed_id' => 8 }, rule)).to be(false)
    end

    it 'returns false for unknown match_kind' do
      rule = { 'match_kind' => 'bogus', 'match_value' => 'x' }
      expect(TagsApplier.matches?({ 'title' => 'x' }, rule)).to be(false)
    end

    it 'returns false (instead of raising) on a malformed regex' do
      rule = { 'match_kind' => 'regex', 'match_value' => '[unclosed' }
      expect(TagsApplier.matches?({ 'title' => 'whatever' }, rule)).to be(false)
    end

    it 'returns false for empty keyword (avoids matching everything)' do
      rule = { 'match_kind' => 'keyword', 'match_value' => '' }
      expect(TagsApplier.matches?({ 'title' => 'anything', 'content_text' => '' }, rule)).to be(false)
    end
  end

  describe '.matching_tag_ids' do
    it 'returns the ids of every rule that matches' do
      rules = [
        { 'id' => 1, 'match_kind' => 'keyword', 'match_value' => 'ai' },
        { 'id' => 2, 'match_kind' => 'keyword', 'match_value' => 'rust' },
        { 'id' => 3, 'match_kind' => 'feed_id', 'match_value' => '5' }
      ]
      article = { 'title' => 'AI safety news', 'content_text' => 'about ai', 'feed_id' => 5 }
      expect(TagsApplier.matching_tag_ids(article, rules)).to contain_exactly(1, 3)
    end
  end

  describe '.apply_to_existing (backfill)' do
    it 'tags every existing article that matches a new rule and reports the count' do
      feed = FeedsStore.add(url: 'https://example.com/feed.rss')
      ArticlesStore.import(feed_id: feed['id'], entries: [
        { uid: 'a' * 12, title: 'A Ruby Post', url: 'https://example.com/a', author: nil,
          published_at: '2026-05-02T12:00:00Z',
          content_html: '<p>x</p>', content_text: 'ruby talk' },
        { uid: 'b' * 12, title: 'Go on Vacation', url: 'https://example.com/b', author: nil,
          published_at: '2026-05-01T12:00:00Z',
          content_html: '<p>y</p>', content_text: 'go and rest' }
      ])

      tag = TagsStore.add(name: 'ruby', match_kind: 'keyword', match_value: 'ruby')
      tagged = TagsApplier.apply_to_existing(tag['id'])

      expect(tagged).to eq(1)
      a = ArticlesStore.find_by_uid('a' * 12)
      b = ArticlesStore.find_by_uid('b' * 12)
      expect(TagsStore.tags_for_article(a['id']).map { |t| t['name'] }).to include('ruby')
      expect(TagsStore.tags_for_article(b['id'])).to be_empty
    end

    it 'is idempotent — re-running adds zero new article_tags' do
      feed = FeedsStore.add(url: 'https://example.com/feed.rss')
      ArticlesStore.import(feed_id: feed['id'], entries: [{
        uid: 'a' * 12, title: 'A Ruby Post', url: 'https://example.com/a', author: nil,
        published_at: '2026-05-02T12:00:00Z',
        content_html: '<p>x</p>', content_text: 'ruby talk'
      }])
      tag = TagsStore.add(name: 'ruby', match_kind: 'keyword', match_value: 'ruby')

      expect(TagsApplier.apply_to_existing(tag['id'])).to eq(1)
      expect(TagsApplier.apply_to_existing(tag['id'])).to eq(0)
    end
  end
end
