require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'

# STUFF.md #16 follow-up — embed the YouTube player on /article/:uid
# for articles imported from a YouTube channel feed; show a clickable
# thumbnail on /whats-on "To watch today" cards. Helpers parse the
# 11-char video ID out of every common YouTube URL form.

# Helpers are tested via a route-stubbed instance — no need to spin
# up a full Rack round-trip for each URL form.
RSpec.describe 'youtube helpers' do
  let(:helper) { TechFeedReader.new! }

  it 'extracts the 11-char ID from a /watch?v= URL' do
    expect(helper.youtube_video_id('url' => 'https://www.youtube.com/watch?v=dQw4w9WgXcQ')).to eq('dQw4w9WgXcQ')
  end

  it 'extracts the ID from a youtu.be short URL' do
    expect(helper.youtube_video_id('url' => 'https://youtu.be/dQw4w9WgXcQ')).to eq('dQw4w9WgXcQ')
  end

  it 'extracts the ID from a /embed/ URL' do
    expect(helper.youtube_video_id('url' => 'https://www.youtube.com/embed/dQw4w9WgXcQ')).to eq('dQw4w9WgXcQ')
  end

  it 'extracts the ID from a /shorts/ URL' do
    expect(helper.youtube_video_id('url' => 'https://www.youtube.com/shorts/dQw4w9WgXcQ')).to eq('dQw4w9WgXcQ')
  end

  it 'returns nil for non-YouTube URLs' do
    expect(helper.youtube_video_id('url' => 'https://example.com/article')).to be_nil
  end

  it 'returns nil for YouTube URLs without a video ID (channel page)' do
    expect(helper.youtube_video_id('url' => 'https://www.youtube.com/@BBCEarth')).to be_nil
  end

  it 'youtube_embed_url builds the iframe URL when ID is present' do
    expect(helper.youtube_embed_url('url' => 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'))
      .to eq('https://www.youtube.com/embed/dQw4w9WgXcQ')
  end

  it 'youtube_thumbnail_url builds the hqdefault CDN URL' do
    expect(helper.youtube_thumbnail_url('url' => 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'))
      .to eq('https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg')
  end
end

RSpec.describe '/article/:uid YouTube embed' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  def make_youtube_article(uid:, video_id:, title: 'YT video', topic: 'nature')
    feed = FeedsStore.find_by_url('https://www.youtube.com/feeds/videos.xml?channel_id=UCtest') ||
           FeedsStore.add(url: 'https://www.youtube.com/feeds/videos.xml?channel_id=UCtest',
                          title: 'Test YT Channel', topic: topic)
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: uid, title: title,
      url: "https://www.youtube.com/watch?v=#{video_id}",
      author: 'Channel Owner',
      published_at: '2026-05-10T12:00:00Z',
      content_html: '<p>Video description.</p>', content_text: 'Video description.',
      audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
    }])
    ArticlesStore.find_by_uid(uid)
  end

  it 'renders the iframe player on a YouTube article page' do
    make_youtube_article(uid: 'yt000000001', video_id: 'dQw4w9WgXcQ')
    get '/article/yt000000001'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to match(
      %r{<iframe[^>]*src="https://www\.youtube\.com/embed/dQw4w9WgXcQ"}
    )
    # Allow flags so picture-in-picture + fullscreen + autoplay-on-click work.
    expect(last_response.body).to include('allowfullscreen')
    expect(last_response.body).to include('picture-in-picture')
  end

  it 'suppresses the hero image when a YouTube embed is present' do
    feed = FeedsStore.add(url: 'https://www.youtube.com/feeds/videos.xml?channel_id=UCwithlogo',
                          title: 'YT Channel With Logo', topic: 'nature')
    # Set a feed image_url to confirm the suppression works.
    Database.connection.execute('UPDATE feeds SET image_url = ? WHERE id = ?',
                                ['https://example.com/logo.png', feed['id']])
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: 'yt000000002', title: 'Vid 2',
      url: 'https://www.youtube.com/watch?v=abcdefghijk',
      author: nil, published_at: '2026-05-10T12:00:00Z',
      content_html: '<p>x</p>', content_text: 'x',
      audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
    }])
    get '/article/yt000000002'
    expect(last_response.body).not_to match(%r{<img class="article-hero"[^>]*logo\.png})
  end

  it 'does NOT render the iframe for a non-YouTube article' do
    feed = FeedsStore.add(url: 'https://example.com/feed.rss', title: 'Plain feed')
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: 'plain000001', title: 'Plain article',
      url: 'https://example.com/post', author: nil,
      published_at: '2026-05-10T12:00:00Z',
      content_html: '<p>x</p>', content_text: 'x',
      audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
    }])
    get '/article/plain000001'
    expect(last_response.body).not_to match(%r{<iframe[^>]*youtube\.com/embed})
  end
end

RSpec.describe 'GET / To watch today thumbnails' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'renders a YouTube thumbnail + play overlay on each watch card' do
    # Seed read_state activity so / hits the returning-user path
    # (anonymous home is the marketing pitch).
    require_relative '../app/read_state_store'
    feed = FeedsStore.add(url: 'https://www.youtube.com/feeds/videos.xml?channel_id=UCwhatson',
                          title: 'WO Nature', topic: 'nature')
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: 'whatsonwatch1', title: 'Today nature video',
      url: 'https://www.youtube.com/watch?v=zzzzzzzzzzz',
      author: nil, published_at: Time.now.utc.iso8601,
      content_html: '<p>x</p>', content_text: 'x',
      audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
    }])
    ReadStateStore.mark_bookmarked(ArticlesStore.find_by_uid('whatsonwatch1')['id'], value: true)

    get '/'
    expect(last_response.body).to include('To watch today')
    expect(last_response.body).to include('https://i.ytimg.com/vi/zzzzzzzzzzz/hqdefault.jpg')
    expect(last_response.body).to include('whats-on-watch-play')
  end
end
