require_relative 'spec_helper'
require 'date'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/read_state_store'
require_relative '../app/sports_follows_store'

# STUFF.md #17 — What's On Today. Lives at / for returning users now
# (the dedicated /whats-on URL is just a 301 → /). To trigger the
# returning-user branch we need at least one read_state row, which
# the seeded article gets via mark_bookmarked in seed_returning!.

def seed_returning!
  feed = FeedsStore.find_by_url('https://example.com/whatson-sentinel') ||
         FeedsStore.add(url: 'https://example.com/whatson-sentinel', title: 'Sentinel feed')
  ArticlesStore.import(feed_id: feed['id'], entries: [{
    uid: 'whatson_sentinel', title: 'Activity sentinel',
    url: 'https://example.com/sentinel', author: nil,
    published_at: '2000-01-01T00:00:00Z',  # old: not in "today" buckets
    content_html: '<p>x</p>', content_text: 'x',
    audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
  }])
  ReadStateStore.mark_bookmarked(ArticlesStore.find_by_uid('whatson_sentinel')['id'], value: true)
end

def make_today_article(uid:, title:, audio_url: nil, topic: 'technology',
                       feed_url: 'https://x.com/whatson', url: nil)
  feed = FeedsStore.find_by_url(feed_url) ||
         FeedsStore.add(url: feed_url, title: 'Whats On Spec', topic: topic)
  ArticlesStore.import(feed_id: feed['id'], entries: [{
    uid: uid, title: title, url: url || "https://x.com/#{uid}", author: nil,
    published_at: Time.now.utc.iso8601,
    content_html: "<p>#{title}</p>", content_text: title,
    audio_url: audio_url, audio_mime_type: nil, audio_duration_seconds: nil
  }])
  ArticlesStore.find_by_uid(uid)
end

RSpec.describe "GET / What's On Today (returning user)" do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'shows the empty-state when activity exists but nothing matches today' do
    seed_returning!
    get '/'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include("What's On Today")
    expect(last_response.body).to include('Quiet day')
  end

  it 'renders today\'s article in the To read section' do
    seed_returning!
    make_today_article(uid: 'whatson_read01', title: 'Tech read today')
    get '/'
    expect(last_response.body).to include('To read today')
    expect(last_response.body).to include('Tech read today')
    expect(last_response.body).not_to include('Quiet day')
  end

  it 'segregates podcasts (audio_url) into the To listen section' do
    seed_returning!
    make_today_article(uid: 'whatson_pod001', title: 'Pod ep today',
                       audio_url: 'https://x.com/p.mp3')
    get '/'
    expect(last_response.body).to include('To listen today')
    expect(last_response.body).to include('Pod ep today')
    read_section = last_response.body[/<h3>📰 To read today.*?<\/section>/m]
    expect(read_section).to be_nil
  end

  # Phase 3 (2026-05-12) — bus mode discovery chip.
  it 'renders a "short for the bus" chip when today has any ≤15-min podcast episodes' do
    seed_returning!
    feed = FeedsStore.find_by_url('https://x.com/buspod') ||
           FeedsStore.add(url: 'https://x.com/buspod', title: 'Bus Pod')
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: 'buspod0001', title: 'Short ep',
      url: 'https://x.com/buspod-ep', author: nil,
      published_at: Time.now.utc.iso8601,
      content_html: '<p>x</p>', content_text: 'x',
      audio_url: 'https://x.com/bus.mp3',
      audio_mime_type: 'audio/mpeg',
      audio_duration_seconds: 600  # 10 minutes — under the 15m cap
    }])
    get '/'
    expect(last_response.body).to include('whats-on-bus-chip')
    expect(last_response.body).to include('short for the bus')
    expect(last_response.body).to match(%r{href="/bus"})
  end

  it 'does NOT render the bus chip when nothing today is ≤15 min' do
    seed_returning!
    feed = FeedsStore.find_by_url('https://x.com/longpod') ||
           FeedsStore.add(url: 'https://x.com/longpod', title: 'Long Pod')
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: 'longpod0001', title: 'Long ep',
      url: 'https://x.com/longpod-ep', author: nil,
      published_at: Time.now.utc.iso8601,
      content_html: '<p>x</p>', content_text: 'x',
      audio_url: 'https://x.com/long.mp3',
      audio_mime_type: 'audio/mpeg',
      audio_duration_seconds: 5400  # 90 minutes — over the bus cap
    }])
    get '/'
    expect(last_response.body).to include('To listen today')
    expect(last_response.body).not_to include('whats-on-bus-chip')
  end

  it 'puts ANY article with a YouTube URL in the To watch section (Phase 2 — was: topic=nature only)' do
    seed_returning!
    # Nature YouTube — like before.
    make_today_article(uid: 'whatson_vid001', title: 'BBC nature today',
                       topic: 'nature', feed_url: 'https://x.com/whatson-nature',
                       url: 'https://www.youtube.com/watch?v=naturevid_0')
    # Sports YouTube — would have been read in pre-Phase-2; now lands in watch.
    make_today_article(uid: 'whatson_vid002', title: 'NFL highlight today',
                       topic: 'sports', feed_url: 'https://x.com/whatson-nfl',
                       url: 'https://www.youtube.com/watch?v=sportsvid_1')
    get '/'
    expect(last_response.body).to include('To watch today')
    expect(last_response.body).to include('BBC nature today')
    expect(last_response.body).to include('NFL highlight today')
  end

  it 'puts non-YouTube articles in the To read section regardless of topic' do
    seed_returning!
    make_today_article(uid: 'whatson_natread1', title: 'Nature article (no video)',
                       topic: 'nature', feed_url: 'https://x.com/whatson-nat-rss',
                       url: 'https://example.com/article')
    get '/'
    expect(last_response.body).to include('To read today')
    expect(last_response.body).to include('Nature article (no video)')
  end
end

RSpec.describe '/whats-on (legacy URL)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'redirects to / with 301 for backwards compatibility' do
    get '/whats-on'
    expect(last_response.status).to eq(301)
    expect(last_response.headers['Location']).to end_with('/')
  end
end

RSpec.describe 'header nav consolidation (STUFF.md #15)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'renders the AI dropdown with Topics / Triage / Digests' do
    get '/admin/dashboard'
    body = last_response.body
    ai_block = body[/<div class="nav-dropdown[^"]*">\s*<button[^>]*>AI[\s\S]*?<\/div>\s*<\/div>/]
    expect(ai_block).not_to be_nil
    expect(ai_block).to include('href="/topics"')
    expect(ai_block).to include('href="/triage"')
    expect(ai_block).to include('href="/digests"')
  end

  it 'renders the Manage dropdown with Feeds / Tags' do
    get '/admin/dashboard'
    body = last_response.body
    manage_block = body[/<div class="nav-dropdown[^"]*">\s*<button[^>]*>Manage[\s\S]*?<\/div>\s*<\/div>/]
    expect(manage_block).not_to be_nil
    expect(manage_block).to include('href="/feeds"')
    expect(manage_block).to include('href="/tags"')
  end

  it 'renders the Search icon link' do
    get '/admin/dashboard'
    expect(last_response.body).to match(%r{<a href="/search"[^>]*nav-search-icon})
  end

  it 'highlights AI dropdown active when on /triage' do
    get '/triage'
    expect(last_response.body).to match(%r{<div class="nav-dropdown active">\s*<button[^>]*>AI})
  end

  it 'highlights Manage dropdown active when on /feeds' do
    get '/feeds'
    expect(last_response.body).to match(%r{<div class="nav-dropdown active">\s*<button[^>]*>Manage})
  end
end

RSpec.describe 'FeedCatalog Nature & Documentary (STUFF.md #16)' do
  it 'declares the nature topic + youtube_nature category' do
    expect(FeedCatalog::TOPICS.keys).to include(:nature)
    expect(FeedCatalog::CATEGORIES.keys).to include(:youtube_nature)
    expect(FeedCatalog::CATEGORY_TO_TOPIC[:youtube_nature]).to eq(:nature)
  end

  it 'every YouTube seed entry uses the standard channel-feed URL pattern' do
    yt = FeedCatalog.all.select { |e| e[:category] == :youtube_nature }
    expect(yt.length).to be >= 5
    yt.each do |e|
      expect(e[:url]).to match(%r{\Ahttps://www\.youtube\.com/feeds/videos\.xml\?channel_id=UC[\w-]+\z})
    end
  end
end
