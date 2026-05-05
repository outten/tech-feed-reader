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
    # Episode-level cover art is also persisted on the article row.
    expect(audio['image_url']).to eq('https://cdn.example.com/ep-12-art.jpg')
  end

  it 'persists per-entry image_url through ArticlesStore.import (when the feed declares one)' do
    feed   = FeedsStore.add(url: 'https://example.com/podcast/feed', title: 'Test Podcast Show')
    parsed = FeedParser.parse(body, feed_url: feed['url'])
    ArticlesStore.import(feed_id: feed['id'], entries: parsed[:entries])

    ep11 = ArticlesStore.recent(limit: 10).find { |r| r['title'].start_with?('Episode 11') }
    expect(ep11['image_url']).to be_nil  # ep11 has no per-item itunes:image
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
    it 'tags podcast rows with the headphone icon (and the article rows with the page icon)' do
      feed   = FeedsStore.add(url: 'https://example.com/podcast/feed', title: 'Test Podcast Show')
      parsed = FeedParser.parse(body, feed_url: feed['url'])
      ArticlesStore.import(feed_id: feed['id'], entries: parsed[:entries])

      # Add one non-audio article so we can assert both icons appear.
      ArticlesStore.import(feed_id: feed['id'], entries: [{
        uid: 'plainarticle1', title: 'Plain post',
        url: 'https://example.com/plain', author: nil,
        published_at: '2026-05-04T12:00:00Z',
        content_html: '<p>Body</p>', content_text: 'Body',
        audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
      }])

      get '/articles'
      expect(last_response.status).to eq(200)
      # Podcast row: 🎧 in the kind-icon span + .news-item-podcast on <li>
      expect(last_response.body).to include('news-item-podcast')
      expect(last_response.body).to include('🎧')
      expect(last_response.body).to include('aria-label="Podcast episode"')
      # Article row: 📄 + .news-item-article
      expect(last_response.body).to include('news-item-article')
      expect(last_response.body).to include('📄')
      expect(last_response.body).to include('aria-label="Article"')
    end

    it 'opens article links in a new tab so Cmd-W returns to the list' do
      feed = FeedsStore.add(url: 'https://example.com/feed', title: 'Feed')
      ArticlesStore.import(feed_id: feed['id'], entries: [{
        uid: 'newtabarticle', title: 'A',
        url: 'https://example.com/a', author: nil,
        published_at: '2026-05-04T12:00:00Z',
        content_html: '<p>Body</p>', content_text: 'Body',
        audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
      }])

      get '/articles'
      # The headline anchor (the row-main link to /article/UID) carries
      # target="_blank" + rel="noopener".
      expect(last_response.body).to match(%r{<a class="news-row-main" href="/article/newtabarticle"[^>]*target="_blank"[^>]*rel="noopener"})
    end
  end
end
