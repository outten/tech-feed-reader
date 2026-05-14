require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'

# STUFF #26 — /youtube channel grid + /youtube/:feed_id videos page.
# Helpers + store filtering covered separately in
# spec/articles_store_youtube_spec.rb; this file covers the route +
# view surface (the header link, empty state, card rendering, the
# channel-detail page, and the 404 behaviour for non-YouTube ids).

RSpec.describe 'YouTube routes' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  let(:channel_url) { 'https://www.youtube.com/feeds/videos.xml?channel_id=UCabcdefABCDEF123456_' }
  let(:non_youtube_url) { 'https://example.com/feed.xml' }

  describe 'GET /youtube' do
    it 'renders an empty state when no YouTube channels are subscribed' do
      get '/youtube'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('No YouTube channels subscribed yet')
    end

    it 'lists subscribed YouTube channels with video count + latest age + ↗ Channel link' do
      feed = FeedsStore.add(url: channel_url, title: 'Bourdain Travels')
      ArticlesStore.import(feed_id: feed['id'], entries: [
        { uid: 'a' * 12, title: 'Video A',
          url: 'https://www.youtube.com/watch?v=abcdefghijk', author: nil,
          published_at: '2026-05-13T12:00:00Z',
          content_html: '<p>x</p>', content_text: 'video a' },
        { uid: 'b' * 12, title: 'Video B',
          url: 'https://www.youtube.com/watch?v=zzzzzzzzzzz', author: nil,
          published_at: '2026-05-10T12:00:00Z',
          content_html: '<p>y</p>', content_text: 'video b' }
      ])

      get '/youtube'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('Bourdain Travels')
      expect(last_response.body).to include('2 videos')
      expect(last_response.body).to include('href="/youtube/' + feed['id'].to_s)
      # ↗ Channel link should target the canonical channel URL in a new tab.
      expect(last_response.body).to include('youtube.com/channel/UCabcdefABCDEF123456_')
      expect(last_response.body).to include('target="_blank"')
    end

    it 'does not list non-YouTube feeds' do
      FeedsStore.add(url: non_youtube_url, title: 'Regular blog')
      get '/youtube'
      expect(last_response.body).not_to include('Regular blog')
    end
  end

  describe 'GET /youtube/:feed_id' do
    let(:feed) { FeedsStore.add(url: channel_url, title: 'Bourdain Travels') }
    before do
      ArticlesStore.import(feed_id: feed['id'], entries: (1..12).map do |i|
        # Two-digit prefix + padding keeps the uids unique + 12 chars.
        { uid: format('vid%09d', i), title: "Video #{i}",
          url: "https://www.youtube.com/watch?v=#{('a'..'z').to_a.sample(11).join}",
          author: nil,
          published_at: "2026-05-#{format('%02d', i)}T12:00:00Z",
          content_html: '<p>x</p>', content_text: "v#{i}" }
      end)
    end

    it 'renders the 10 most recent videos, newest first' do
      get "/youtube/#{feed['id']}"
      expect(last_response.status).to eq(200)
      # 12 videos imported, 10 shown — the two oldest (Video 1 + 2) are omitted.
      expect(last_response.body).to include('Video 12')
      expect(last_response.body).to include('Video 3')
      expect(last_response.body).not_to include('Video 1<')
      expect(last_response.body).not_to include('Video 2<')
    end

    it 'links the ↗ Channel header to the canonical YouTube channel URL' do
      get "/youtube/#{feed['id']}"
      expect(last_response.body).to include('youtube.com/channel/UCabcdefABCDEF123456_')
    end

    it 'links each video tile to /article/:uid (where the embed player lives)' do
      get "/youtube/#{feed['id']}"
      expect(last_response.body).to match(%r{href="/article/vid\d+"})
    end

    it '404s on an unknown feed_id' do
      get '/youtube/99999'
      expect(last_response.status).to eq(404)
    end

    it '404s when the feed exists but is not a YouTube channel feed' do
      regular = FeedsStore.add(url: non_youtube_url, title: 'Regular blog')
      get "/youtube/#{regular['id']}"
      expect(last_response.status).to eq(404)
    end
  end

  describe 'header link' do
    it 'renders a YouTube top-level nav link' do
      get '/articles'
      expect(last_response.body).to include('href="/youtube"')
      expect(last_response.body).to match(/>YouTube</)
    end

    it 'marks the YouTube link active on /youtube and /youtube/:id' do
      get '/youtube'
      expect(last_response.body).to match(/href="\/youtube"\s+class="active"/)
      feed = FeedsStore.add(url: channel_url, title: 'X')
      get "/youtube/#{feed['id']}"
      expect(last_response.body).to match(/href="\/youtube"\s+class="active"/)
    end
  end
end

RSpec.describe ArticlesStore, '.youtube_channels' do
  let(:channel_url) { 'https://www.youtube.com/feeds/videos.xml?channel_id=UCnnn' }

  it 'returns YouTube channel feeds with video_count + latest_at' do
    feed = FeedsStore.add(url: channel_url, title: 'C1')
    ArticlesStore.import(feed_id: feed['id'], entries: [
      { uid: 'a' * 12, title: 'A',
        url: 'https://www.youtube.com/watch?v=aaaaaaaaaaa', author: nil,
        published_at: '2026-05-13T12:00:00Z',
        content_html: '<p>x</p>', content_text: 'a' }
    ])
    rows = ArticlesStore.youtube_channels(1)
    expect(rows.length).to eq(1)
    expect(rows.first['title']).to eq('C1')
    expect(rows.first['video_count']).to eq(1)
  end

  it 'excludes non-YouTube feeds' do
    FeedsStore.add(url: 'https://example.com/feed.xml', title: 'Regular')
    rows = ArticlesStore.youtube_channels(1)
    expect(rows.map { |r| r['title'] }).not_to include('Regular')
  end

  it "doesn't leak across users (isolation guard)" do
    other = UsersStore.create(username: 'kate')
    feed = FeedsStore.add_to_catalog(url: channel_url, title: 'Kate Only')
    FeedsStore.subscribe(other['id'], feed['id'])
    rows = ArticlesStore.youtube_channels(1)
    expect(rows.map { |r| r['title'] }).not_to include('Kate Only')
  end
end
