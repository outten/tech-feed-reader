require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'

# Reading-time estimate. ~200 wpm; nil for short content (<100 words),
# audio (podcasts), and video (YouTube articles). Capped at 60 min.

RSpec.describe 'reading_time_minutes helper' do
  let(:helper) { TechFeedReader.new! }

  it 'returns nil for empty content' do
    expect(helper.reading_time_minutes('content_text' => '')).to be_nil
  end

  it 'returns nil for <100 words (sub-minute pills are noise)' do
    short = 'a ' * 50
    expect(helper.reading_time_minutes('content_text' => short)).to be_nil
  end

  it 'returns 1 minute for ~200 words' do
    text = 'word ' * 200
    expect(helper.reading_time_minutes('content_text' => text)).to eq(1)
  end

  it 'rounds up (ceil) — 250 words = 2 min, not 1' do
    text = 'word ' * 250
    expect(helper.reading_time_minutes('content_text' => text)).to eq(2)
  end

  it 'caps at 60 minutes for very long articles' do
    text = 'word ' * 50_000
    expect(helper.reading_time_minutes('content_text' => text)).to eq(60)
  end

  it 'returns nil for podcasts (audio_url present)' do
    podcast = { 'content_text' => 'word ' * 500, 'audio_url' => 'https://x.com/p.mp3' }
    expect(helper.reading_time_minutes(podcast)).to be_nil
  end

  it 'returns nil for YouTube articles' do
    video = { 'content_text' => 'word ' * 500, 'url' => 'https://www.youtube.com/watch?v=dQw4w9WgXcQ' }
    expect(helper.reading_time_minutes(video)).to be_nil
  end
end

RSpec.describe 'reading-time pill rendering' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  def seed_article(uid:, content:, audio_url: nil, url: nil)
    feed = FeedsStore.find_by_url('https://example.com/reading-time') ||
           FeedsStore.add(url: 'https://example.com/reading-time', title: 'RT')
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: uid, title: "T-#{uid}",
      url: url || "https://example.com/#{uid}", author: nil,
      published_at: '2026-05-10T12:00:00Z',
      content_html: "<p>#{content}</p>", content_text: content,
      audio_url: audio_url, audio_mime_type: nil, audio_duration_seconds: nil
    }])
  end

  it '/articles renders the reading-time pill for long-enough articles' do
    seed_article(uid: 'rtlong00001', content: ('word ' * 500))
    get '/articles'
    expect(last_response.body).to include('news-reading-time')
    expect(last_response.body).to match(/📖 \d+ min/)
  end

  it '/articles does NOT render the pill for podcasts' do
    seed_article(uid: 'rtpodcst001', content: ('word ' * 500),
                 audio_url: 'https://example.com/podcast.mp3')
    get '/articles'
    expect(last_response.body).not_to match(/<span class="news-reading-time"/)
  end

  it '/article/:uid header shows "X min read" for long articles' do
    seed_article(uid: 'rtdetail001', content: ('word ' * 500))
    get '/article/rtdetail001'
    expect(last_response.body).to match(/📖 \d+ min read/)
  end
end
