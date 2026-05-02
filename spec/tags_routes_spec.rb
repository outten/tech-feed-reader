require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/tags_store'

RSpec.describe 'tag routes' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  describe 'POST /tags' do
    it 'adds a rule and reports backfill count' do
      feed = FeedsStore.add(url: 'https://example.com/feed.rss')
      ArticlesStore.import(feed_id: feed['id'], entries: [{
        uid: 'a' * 12, title: 'Ruby Stuff',
        url: 'https://example.com/a', author: nil,
        published_at: '2026-05-02T12:00:00Z',
        content_html: '<p>x</p>', content_text: 'ruby is great'
      }])

      post '/tags', { 'name' => 'ruby', 'match_kind' => 'keyword', 'match_value' => 'ruby' }
      expect(last_response.headers['Location']).to include('notice=added')
      expect(last_response.headers['Location']).to include('tagged=1')
      expect(TagsStore.find_by_name('ruby')).not_to be_nil
    end

    it 'rejects missing fields' do
      post '/tags', { 'name' => '', 'match_kind' => 'keyword', 'match_value' => 'x' }
      expect(last_response.headers['Location']).to include('error=missing-fields')
    end

    it 'rejects invalid match_kind' do
      post '/tags', { 'name' => 'x', 'match_kind' => 'bogus', 'match_value' => 'x' }
      expect(last_response.headers['Location']).to include('error=invalid-kind')
    end

    it 'rejects malformed regex before INSERT' do
      post '/tags', { 'name' => 'bad', 'match_kind' => 'regex', 'match_value' => '[unclosed' }
      expect(last_response.headers['Location']).to include('error=invalid-regex')
      expect(TagsStore.find_by_name('bad')).to be_nil
    end

    it 'reports duplicate names' do
      TagsStore.add(name: 'ruby', match_kind: 'keyword', match_value: 'ruby')
      post '/tags', { 'name' => 'ruby', 'match_kind' => 'keyword', 'match_value' => 'rails' }
      expect(last_response.headers['Location']).to include('error=duplicate-name')
    end
  end

  describe 'POST /tags/:id/delete' do
    it 'removes the tag and reports notice=removed' do
      tag = TagsStore.add(name: 'ruby', match_kind: 'keyword', match_value: 'ruby')
      post "/tags/#{tag['id']}/delete"
      expect(last_response.headers['Location']).to include('notice=removed')
      expect(TagsStore.find(tag['id'])).to be_nil
    end

    it 'reports not-found for an unknown id' do
      post '/tags/999/delete'
      expect(last_response.headers['Location']).to include('error=not-found')
    end
  end

  describe 'POST /article/:uid/tag/:tag_id' do
    let(:feed) { FeedsStore.add(url: 'https://example.com/feed.rss') }
    let(:tag)  { TagsStore.add(name: 'manual', match_kind: 'keyword', match_value: 'unrelated') }
    let(:article) do
      ArticlesStore.import(feed_id: feed['id'], entries: [{
        uid: 'a' * 12, title: 'Hello', url: 'https://example.com/a', author: nil,
        published_at: '2026-05-02T12:00:00Z',
        content_html: '<p>x</p>', content_text: 'no match here'
      }])
      ArticlesStore.find_by_uid('a' * 12)
    end

    it 'adds the tag to the article (default value=add)' do
      tag # force lazy let
      post "/article/#{article['uid']}/tag/#{tag['id']}"
      expect(TagsStore.tags_for_article(article['id']).map { |t| t['name'] }).to include('manual')
    end

    it 'removes the tag when value=remove' do
      TagsStore.tag_article(article['id'], tag['id'])
      post "/article/#{article['uid']}/tag/#{tag['id']}", { 'value' => 'remove' }
      expect(TagsStore.tags_for_article(article['id'])).to be_empty
    end

    it '404s for an unknown article uid' do
      post "/article/zzzzzzzzzzzz/tag/#{tag['id']}"
      expect(last_response.status).to eq(404)
    end

    it '404s for an unknown tag id' do
      post "/article/#{article['uid']}/tag/999"
      expect(last_response.status).to eq(404)
    end
  end

  describe '/articles?tag=N' do
    it 'returns only articles with that tag' do
      feed = FeedsStore.add(url: 'https://example.com/feed.rss')
      ArticlesStore.import(feed_id: feed['id'], entries: [
        { uid: 'a' * 12, title: 'Tagged article', url: 'https://example.com/a', author: nil,
          published_at: '2026-05-02T12:00:00Z',
          content_html: '<p>x</p>', content_text: 'mentions ruby' },
        { uid: 'b' * 12, title: 'Different', url: 'https://example.com/b', author: nil,
          published_at: '2026-05-01T12:00:00Z',
          content_html: '<p>y</p>', content_text: 'mentions go' }
      ])

      tag = TagsStore.add(name: 'ruby', match_kind: 'keyword', match_value: 'ruby')
      TagsApplier.apply_to_existing(tag['id'])

      get "/articles?tag=#{tag['id']}"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('Tagged article')
      expect(last_response.body).not_to include('Different')
    end
  end
end
