require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'

def seed_pbs_feed(url: 'https://www.pbs.org/newshour/feeds/rss/headlines', title: 'PBS NewsHour')
  FeedsStore.find_by_url(url) ||
    FeedsStore.add(url: url, title: title, topic: 'pbs', subscriber_id: 1)
end

def seed_pbs_article(feed_id:, uid:, title:, audio_url: nil, article_url: nil)
  ArticlesStore.import(feed_id: feed_id, entries: [{
    uid: uid, title: title,
    url: article_url || "https://www.pbs.org/article/#{uid}",
    author: nil, published_at: Time.now.utc.iso8601,
    content_html: "<p>#{title}</p>", content_text: title,
    audio_url: audio_url, audio_mime_type: nil, audio_duration_seconds: nil
  }])
  ArticlesStore.find_by_uid(uid)
end

RSpec.describe 'GET /pbs/:feed_id — PBS show detail page' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'returns 200 and shows the feed title and article titles for a subscribed PBS feed' do
    feed = seed_pbs_feed
    seed_pbs_article(feed_id: feed['id'], uid: 'pbsshow0001', title: 'Top story today')
    get "/pbs/#{feed['id']}"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include(feed['title'])
    expect(last_response.body).to include('Top story today')
  end

  it 'returns 404 for a non-PBS feed (wrong topic)' do
    other_feed = FeedsStore.find_by_url('https://example.com/not-pbs') ||
                 FeedsStore.add(url: 'https://example.com/not-pbs', title: 'Not PBS', topic: 'general', subscriber_id: 1)
    get "/pbs/#{other_feed['id']}"
    expect(last_response.status).to eq(404)
  end

  it 'shows a Listen link for audio episodes and a Read link for text-only articles' do
    feed = seed_pbs_feed(url: 'https://pbs.org/feeds/rss/audio', title: 'PBS Audio')
    seed_pbs_article(
      feed_id: feed['id'], uid: 'pbsaudio001', title: 'Audio episode',
      audio_url: 'https://cdn.pbs.org/audio.mp3'
    )
    seed_pbs_article(
      feed_id: feed['id'], uid: 'pbstext0001', title: 'Text article'
    )
    get "/pbs/#{feed['id']}"
    expect(last_response.body).to include('Listen')
    expect(last_response.body).to include('Read')
  end

  it 'shows a Watch link (external) for YouTube-URL articles' do
    feed = seed_pbs_feed(url: 'https://www.youtube.com/feeds/videos.xml?channel_id=UCxxxxPBS', title: 'PBS YouTube')
    seed_pbs_article(
      feed_id: feed['id'], uid: 'pbsytvid01', title: 'PBS YouTube video',
      article_url: 'https://www.youtube.com/watch?v=pbsvid0001'
    )
    get "/pbs/#{feed['id']}"
    expect(last_response.body).to include('Watch')
    expect(last_response.body).to include('target="_blank"')
  end
end
