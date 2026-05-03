require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/feed_parser'

RSpec.describe 'podcast end-to-end' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  let(:body) { File.read(File.expand_path('fixtures/podcast_rss.xml', __dir__)) }

  it 'persists audio_url, mime type, and duration through ArticlesStore.import' do
    feed   = FeedsStore.add(url: 'https://example.com/podcast/feed', title: 'Test Podcast Show')
    parsed = FeedParser.parse(body, feed_url: feed['url'])
    inserted = ArticlesStore.import(feed_id: feed['id'], entries: parsed[:entries])
    expect(inserted).to eq(parsed[:entries].length)

    rows  = ArticlesStore.recent(limit: 10)
    audio = rows.find { |r| r['title'].start_with?('Episode 12') }
    expect(audio['audio_url']).to eq('https://cdn.example.com/audio/ep-12.mp3')
    expect(audio['audio_mime_type']).to eq('audio/mpeg')
    expect(audio['audio_duration_seconds']).to eq(1 * 3600 + 23 * 60 + 45)
  end

  describe 'GET /article/:uid for a podcast episode' do
    it 'renders the play-episode button (with audio metadata in data-attrs) and the PODCAST badge' do
      feed   = FeedsStore.add(url: 'https://example.com/podcast/feed', title: 'Test Podcast Show')
      parsed = FeedParser.parse(body, feed_url: feed['url'])
      ArticlesStore.import(feed_id: feed['id'], entries: parsed[:entries])

      ep12 = ArticlesStore.recent(limit: 10).find { |r| r['title'].start_with?('Episode 12') }
      get "/article/#{ep12['uid']}"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('class="badge podcast-badge"')
      expect(last_response.body).to include('PODCAST')
      # New structure: a "Play episode" button wired to the global
      # mini-player. No <audio> on the article page itself; audio
      # element lives in the layout under #global-player.
      expect(last_response.body).to include('class="play-episode')
      expect(last_response.body).to include('data-audio-url="https://cdn.example.com/audio/ep-12.mp3"')
      expect(last_response.body).to include('global-player.js')
    end
  end

  describe 'GET /article/:uid for a non-podcast article' do
    it 'omits the play-episode button and the PODCAST badge' do
      feed = FeedsStore.add(url: 'https://example.com/feed.rss', title: 'Plain blog')
      ArticlesStore.import(feed_id: feed['id'], entries: [{
        uid: 'plainblogab12', title: 'Plain post',
        url: 'https://example.com/plain', author: nil,
        published_at: '2026-05-02T12:00:00Z',
        content_html: '<p>Body</p>', content_text: 'Body',
        audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
      }])

      get '/article/plainblogab12'
      expect(last_response.status).to eq(200)
      expect(last_response.body).not_to include('class="play-episode')
      expect(last_response.body).not_to include('PODCAST')
    end
  end

  describe 'GET /articles' do
    it 'shows the PODCAST badge on rows whose article has audio_url' do
      feed   = FeedsStore.add(url: 'https://example.com/podcast/feed', title: 'Test Podcast Show')
      parsed = FeedParser.parse(body, feed_url: feed['url'])
      ArticlesStore.import(feed_id: feed['id'], entries: parsed[:entries])

      get '/articles'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('class="badge podcast-badge"')
    end
  end
end
