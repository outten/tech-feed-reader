require_relative 'spec_helper'
require 'date'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/sports_follows_store'

# STUFF.md #17 — What's On Today.
# Personalized one-page surface that pulls from data we already track
# and filters to today's rows.

def make_today_article(uid:, title:, audio_url: nil, topic: 'technology',
                       feed_url: 'https://x.com/whatson')
  feed = FeedsStore.find_by_url(feed_url) ||
         FeedsStore.add(url: feed_url, title: 'Whats On Spec', topic: topic)
  ArticlesStore.import(feed_id: feed['id'], entries: [{
    uid: uid, title: title, url: "https://x.com/#{uid}", author: nil,
    published_at: Time.now.utc.iso8601,
    content_html: "<p>#{title}</p>", content_text: title,
    audio_url: audio_url, audio_mime_type: nil, audio_duration_seconds: nil
  }])
  ArticlesStore.find_by_uid(uid)
end

RSpec.describe 'GET /whats-on' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'renders the page header even with no content (empty-state message)' do
    get '/whats-on'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include("What's On Today")
    expect(last_response.body).to include('Quiet day')
  end

  it 'renders today\'s article in the To read section' do
    make_today_article(uid: 'whatson_read01', title: 'Tech read today')
    get '/whats-on'
    expect(last_response.body).to include('To read today')
    expect(last_response.body).to include('Tech read today')
    expect(last_response.body).not_to include('Quiet day')
  end

  it 'segregates podcasts (audio_url) into the To listen section' do
    make_today_article(uid: 'whatson_pod001', title: 'Pod ep today',
                       audio_url: 'https://x.com/p.mp3')
    get '/whats-on'
    expect(last_response.body).to include('To listen today')
    expect(last_response.body).to include('Pod ep today')
    # Should NOT show under To read.
    read_section = last_response.body[/<h3>📰 To read today.*?<\/section>/m]
    expect(read_section).to be_nil
  end

  it 'puts nature-topic articles in the To watch section' do
    make_today_article(uid: 'whatson_vid001', title: 'BBC nature today',
                       topic: 'nature', feed_url: 'https://x.com/whatson-nature')
    get '/whats-on'
    expect(last_response.body).to include('To watch today')
    expect(last_response.body).to include('BBC nature today')
  end
end

RSpec.describe 'header nav consolidation (STUFF.md #15)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'renders the AI dropdown with Topics / Triage / Digests' do
    get '/dashboard'
    body = last_response.body
    ai_block = body[/<div class="nav-dropdown[^"]*">\s*<button[^>]*>AI[\s\S]*?<\/div>\s*<\/div>/]
    expect(ai_block).not_to be_nil
    expect(ai_block).to include('href="/topics"')
    expect(ai_block).to include('href="/triage"')
    expect(ai_block).to include('href="/digests"')
  end

  it 'renders the Manage dropdown with Feeds / Tags' do
    get '/dashboard'
    body = last_response.body
    manage_block = body[/<div class="nav-dropdown[^"]*">\s*<button[^>]*>Manage[\s\S]*?<\/div>\s*<\/div>/]
    expect(manage_block).not_to be_nil
    expect(manage_block).to include('href="/feeds"')
    expect(manage_block).to include('href="/tags"')
  end

  it 'renders the Search icon link' do
    get '/dashboard'
    expect(last_response.body).to match(%r{<a href="/search"[^>]*nav-search-icon})
  end

  it 'renders the new What\'s On top-level nav link' do
    get '/dashboard'
    expect(last_response.body).to match(%r{<a href="/whats-on"})
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
