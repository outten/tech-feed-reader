require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'

def seed_lucky_feed(url:, title:, topic: 'general')
  FeedsStore.find_by_url(url) ||
    FeedsStore.add(url: url, title: title, topic: topic, subscriber_id: 1)
end

def seed_lucky_article(feed_id:, uid:, title:, audio_url: nil, article_url: nil)
  ArticlesStore.import(feed_id: feed_id, entries: [{
    uid: uid, title: title,
    url: article_url || "https://example.com/#{uid}",
    author: nil, published_at: Time.now.utc.iso8601,
    content_html: "<p>#{title}</p>", content_text: title,
    audio_url: audio_url, audio_mime_type: nil, audio_duration_seconds: nil
  }])
  ArticlesStore.find_by_uid(uid)
end

RSpec.describe 'GET /lucky — I Feel Lucky' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'returns 200 and renders article titles' do
    feed = seed_lucky_feed(url: 'https://example.com/rss/lucky1', title: 'Lucky Feed')
    seed_lucky_article(feed_id: feed['id'], uid: 'lucky00001', title: 'A lucky article')
    get '/lucky'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('A lucky article')
  end

  it 'shows empty state when user has no subscribed articles' do
    get '/lucky'
    expect(last_response.status).to eq(200)
  end

  it 'shows a Listen link for audio articles' do
    feed = seed_lucky_feed(url: 'https://example.com/rss/luckyaudio', title: 'Lucky Audio')
    seed_lucky_article(
      feed_id: feed['id'], uid: 'luckyaud01', title: 'Lucky audio ep',
      audio_url: 'https://cdn.example.com/ep.mp3'
    )
    get '/lucky'
    expect(last_response.body).to include('Listen')
  end

  it 'shows a Watch link for YouTube URL articles' do
    feed = seed_lucky_feed(url: 'https://example.com/rss/luckyvid', title: 'Lucky Video')
    seed_lucky_article(
      feed_id: feed['id'], uid: 'luckyvid01', title: 'Lucky YouTube video',
      article_url: 'https://www.youtube.com/watch?v=lucky123'
    )
    get '/lucky'
    expect(last_response.body).to include('Watch')
    expect(last_response.body).to include('target="_blank"')
  end

  it 'shows a Read link for text-only articles' do
    feed = seed_lucky_feed(url: 'https://example.com/rss/luckytext', title: 'Lucky Text')
    seed_lucky_article(feed_id: feed['id'], uid: 'luckytext1', title: 'Lucky text article')
    get '/lucky'
    expect(last_response.body).to include('Read')
  end

  it 'renders the dice icon link with data-turbo-prefetch=false' do
    get '/lucky'
    expect(last_response.body).to include('href="/lucky"')
    expect(last_response.body).to include('data-turbo-prefetch="false"')
  end
end
