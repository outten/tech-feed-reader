require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'

def seed_feed(url:, title:, topic: 'general')
  FeedsStore.find_by_url(url) ||
    FeedsStore.add(url: url, title: title, topic: topic, subscriber_id: 1)
end

def seed_feed_article(feed_id:, uid:, title:, audio_url: nil, article_url: nil)
  ArticlesStore.import(feed_id: feed_id, entries: [{
    uid: uid, title: title,
    url: article_url || "https://example.com/article/#{uid}",
    author: nil, published_at: Time.now.utc.iso8601,
    content_html: "<p>#{title}</p>", content_text: title,
    audio_url: audio_url, audio_mime_type: nil, audio_duration_seconds: nil
  }])
  ArticlesStore.find_by_uid(uid)
end

RSpec.describe 'GET /feeds/:feed_id — per-feed content page' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'returns 200 and shows feed title and article titles for a subscribed feed' do
    feed = seed_feed(url: 'https://example.com/rss/show1', title: 'My Show')
    seed_feed_article(feed_id: feed['id'], uid: 'feedshow0001', title: 'First episode')
    get "/feeds/#{feed['id']}"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('My Show')
    expect(last_response.body).to include('First episode')
  end

  it 'returns 404 for a feed the user is not subscribed to' do
    get '/feeds/999999'
    expect(last_response.status).to eq(404)
  end

  it 'shows a Listen link for audio articles' do
    feed = seed_feed(url: 'https://example.com/rss/audio', title: 'Audio Feed')
    seed_feed_article(
      feed_id: feed['id'], uid: 'feedaudio001', title: 'Audio ep',
      audio_url: 'https://cdn.example.com/ep.mp3'
    )
    get "/feeds/#{feed['id']}"
    expect(last_response.body).to include('Listen')
  end

  it 'shows a Watch link for YouTube URL articles' do
    feed = seed_feed(url: 'https://example.com/rss/video', title: 'Video Feed')
    seed_feed_article(
      feed_id: feed['id'], uid: 'feedvideo01', title: 'YouTube video',
      article_url: 'https://www.youtube.com/watch?v=abc123'
    )
    get "/feeds/#{feed['id']}"
    expect(last_response.body).to include('Watch')
    expect(last_response.body).to include('target="_blank"')
  end

  it 'shows a Read link for text-only articles' do
    feed = seed_feed(url: 'https://example.com/rss/text', title: 'Text Feed')
    seed_feed_article(feed_id: feed['id'], uid: 'feedtext001', title: 'A text article')
    get "/feeds/#{feed['id']}"
    expect(last_response.body).to include('Read')
  end
end
