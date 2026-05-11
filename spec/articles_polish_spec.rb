require_relative 'spec_helper'
require 'date'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'

# STUFF.md follow-up — /articles polish bundle:
#   • Context line under the header (count + freshest source)
#   • Day-group dividers (Today / Yesterday / Earlier this week / …)
#   • Bigger left-anchored thumbnails (with podcast / YouTube /
#     feed-image fallbacks)
#   • Source-cluster ribbons for runs of 3+ consecutive same-feed rows

RSpec.describe '/articles polish' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  def seed_article(uid:, title:, feed:, published_at:, audio_url: nil, image_url: nil, url: nil)
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: uid, title: title,
      url: url || "https://example.com/#{uid}", author: nil,
      published_at: published_at,
      content_html: "<p>#{title}</p>", content_text: title,
      audio_url: audio_url, audio_mime_type: nil, audio_duration_seconds: nil,
      image_url: image_url
    }])
  end

  it 'renders the context line with count + freshest-source hint' do
    feed = FeedsStore.add(url: 'https://example.com/freshest', title: 'Freshest Source')
    seed_article(uid: 'polishctx01', title: 'A fresh article',
                 feed: feed, published_at: Time.now.utc.iso8601)
    get '/articles'
    expect(last_response.body).to match(/articles-context/)
    expect(last_response.body).to include('Freshest Source')
    expect(last_response.body).to include('in last 24h')
  end

  it 'renders day-group dividers in chronological mode' do
    feed = FeedsStore.add(url: 'https://example.com/day-groups', title: 'DG')
    seed_article(uid: 'dgtoday001', title: 'Today article',
                 feed: feed, published_at: Time.now.utc.iso8601)
    seed_article(uid: 'dgyesterday1', title: 'Yesterday article',
                 feed: feed, published_at: (Time.now.utc - 86_400).iso8601)
    seed_article(uid: 'dgolder001', title: 'Old article',
                 feed: feed, published_at: (Time.now.utc - 40 * 86_400).iso8601)
    get '/articles'
    expect(last_response.body).to include('news-day-divider')
    expect(last_response.body).to include('Today')
    expect(last_response.body).to include('Yesterday')
    expect(last_response.body).to match(/Older|Earlier/)
  end

  it 'does NOT render day-group dividers when sort=relevance (ordering would mislead)' do
    feed = FeedsStore.add(url: 'https://example.com/rel-sort', title: 'RS')
    seed_article(uid: 'rsday00001', title: 'A', feed: feed, published_at: Time.now.utc.iso8601)
    get '/articles?sort=relevance&state=unread'
    expect(last_response.body).not_to include('news-day-divider')
  end

  it 'renders a source-cluster ribbon when 3+ consecutive rows share a feed' do
    feed = FeedsStore.add(url: 'https://example.com/cluster', title: 'Cluster Source')
    base = Time.now.utc
    4.times { |i| seed_article(uid: "cluster0000#{i}", title: "Cluster #{i}",
                               feed: feed, published_at: (base - i).iso8601) }
    get '/articles?state=all'
    expect(last_response.body).to match(/news-source-ribbon/)
    expect(last_response.body).to include('Cluster Source')
    expect(last_response.body).to match(/in a row/)
  end

  it 'does NOT render a source-cluster ribbon when filtered to a single feed (the page IS the cluster)' do
    feed = FeedsStore.add(url: 'https://example.com/already-filtered', title: 'AF')
    3.times { |i| seed_article(uid: "af00000#{i}", title: "AF #{i}",
                               feed: feed, published_at: (Time.now.utc - i).iso8601) }
    get "/articles?feed_id=#{feed['id']}"
    expect(last_response.body).not_to include('news-source-ribbon')
  end

  it 'falls back to feed image_url when article has no image (visual rhythm)' do
    feed = FeedsStore.add(url: 'https://example.com/with-logo', title: 'With Logo')
    Database.connection.execute('UPDATE feeds SET image_url = ? WHERE id = ?',
                                ['https://example.com/feed-logo.png', feed['id']])
    seed_article(uid: 'fallback001', title: 'No own image',
                 feed: feed, published_at: Time.now.utc.iso8601, image_url: nil)
    get '/articles'
    expect(last_response.body).to include('feed-logo.png')
  end

  it 'falls back to YouTube hqdefault for video articles' do
    feed = FeedsStore.add(url: 'https://www.youtube.com/feeds/videos.xml?channel_id=UCpolish',
                          title: 'Polish YT', topic: 'nature')
    seed_article(uid: 'ytpolish01', title: 'Polish video',
                 feed: feed, published_at: Time.now.utc.iso8601,
                 url: 'https://www.youtube.com/watch?v=polishvid_1')
    get '/articles'
    expect(last_response.body).to include('https://i.ytimg.com/vi/polishvid_1/hqdefault.jpg')
  end

  it 'renders the thumbnail inside a clickable link (not a bare <img>)' do
    feed = FeedsStore.add(url: 'https://example.com/thumb-link', title: 'TL')
    seed_article(uid: 'thumblink01', title: 'Thumb link',
                 feed: feed, published_at: Time.now.utc.iso8601,
                 image_url: 'https://example.com/thumb.jpg')
    get '/articles'
    expect(last_response.body).to match(
      %r{<a class="news-item-thumb-link" href="/article/thumblink01"[\s\S]*?<img class="news-item-thumb"}
    )
  end
end
