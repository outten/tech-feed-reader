require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/recommendation'

# async-related-articles — the Related panel is deferred off the article render
# path to GET /article/:uid/related (loaded by public/lazy-fragment.js). The
# page must not compute for_article inline; the fragment renders the panel.
RSpec.describe 'Article page Related panel (async-related-articles: deferred)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  def make_article(uid:, title:, content_text:)
    feed = FeedsStore.find_by_url('https://x.com/rel-rss') || FeedsStore.add(url: 'https://x.com/rel-rss', title: 'Rel Feed')
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: uid, title: title, url: "https://x.com/#{uid}", author: nil,
      published_at: '2026-05-06T12:00:00Z', content_html: "<p>#{content_text}</p>",
      content_text: content_text, audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
    }])
    ArticlesStore.find_by_uid(uid)
  end

  describe 'GET /article/:uid (the page)' do
    it 'ships the Related placeholder and does not compute for_article inline' do
      make_article(uid: 'relpage0001', title: 'Apples', content_text: 'apples oranges fruit basket')
      make_article(uid: 'relpage0002', title: 'More fruit', content_text: 'apples oranges fruit great')

      expect(Recommendation).not_to receive(:for_article)
      get '/article/relpage0001'

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('data-fragment-url="/article/relpage0001/related"')
      expect(last_response.body).to include('related-sentinel')
      expect(last_response.body).not_to include('<h3>Related</h3>')
    end
  end

  describe 'GET /article/:uid/related (the deferred fragment)' do
    it 'renders the Related panel when there are FTS matches' do
      make_article(uid: 'relview0001', title: 'Apples and oranges', content_text: 'apples oranges fruit comparison basket')
      make_article(uid: 'relview0002', title: 'More fruit thoughts', content_text: 'apples oranges fruit are great basket')

      get '/article/relview0001/related'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('<h3>Related</h3>')
      expect(last_response.body).to include('More fruit thoughts')
    end

    it 'returns an empty fragment when nothing matches' do
      make_article(uid: 'rellone0001', title: 'Solitude', content_text: 'unique singular xyzzy plugh content')
      get '/article/rellone0001/related'
      expect(last_response.status).to eq(200)
      expect(last_response.body).not_to include('<h3>Related</h3>')
    end

    it '404s for an unknown article' do
      get '/article/doesnotexist/related'
      expect(last_response.status).to eq(404)
    end

    it 'never includes the current article in the panel' do
      make_article(uid: 'relself0001', title: 'Self ref', content_text: 'apples oranges fruit basket recurring terms')
      make_article(uid: 'relself0002', title: 'Other fruit', content_text: 'apples oranges fruit basket recurring terms')
      get '/article/relself0001/related'
      expect(last_response.body).not_to include('href="/article/relself0001"')
    end
  end
end
