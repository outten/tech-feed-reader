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

  # STUFF #30 — bulk-add channels textarea + resolver. The resolver is
  # stubbed at the module level so the route specs don't depend on
  # YouTube being reachable + on a stable HTML shape.
  describe 'GET /youtube — bulk-add form' do
    it 'renders the "+ Add channels" form on the page' do
      get '/youtube'
      expect(last_response.body).to include('+ Add channels')
      expect(last_response.body).to include('name="channels"')
      expect(last_response.body).to include('action="/youtube/subscribe-bulk"')
    end

    it 'shows the supported-shape examples (@handle / handle URL / channel URL)' do
      get '/youtube'
      expect(last_response.body).to include('@PBSNewsHour')
      expect(last_response.body).to include('youtube.com/channel/UC')
    end
  end

  describe 'POST /youtube/subscribe-bulk' do
    def stub_resolver(map)
      allow(Providers::YouTubeChannelResolver).to receive(:resolve) do |input|
        result = map[input.strip]
        if result.is_a?(Hash)
          Providers::YouTubeChannelResolver::Result.new(**result)
        else
          Providers::YouTubeChannelResolver::Result.new(status: :error, error: 'no stub for input')
        end
      end
    end

    it 'subscribes every line that resolves; reports already-subscribed for dupes; reports failures' do
      stub_resolver(
        '@PBSNewsHour' => {
          status: :ok, channel_id: 'UCnp2WgGyc4VyB9HZeUjjeUw', title: 'PBS NewsHour',
          feed_url: 'https://www.youtube.com/feeds/videos.xml?channel_id=UCnp2WgGyc4VyB9HZeUjjeUw'
        },
        '@CNN' => {
          status: :ok, channel_id: 'UCupvZG-5ko_eiXAupbDfxWw', title: 'CNN',
          feed_url: 'https://www.youtube.com/feeds/videos.xml?channel_id=UCupvZG-5ko_eiXAupbDfxWw'
        },
        '@nope' => { status: :not_found, error: 'channel page returned 404' }
      )

      # Pre-subscribe CNN so the second line reports "already subscribed".
      FeedsStore.add(url: 'https://www.youtube.com/feeds/videos.xml?channel_id=UCupvZG-5ko_eiXAupbDfxWw', title: 'CNN')

      # The brand-new PBS NewsHour subscription should enqueue a refresh.
      expect(FeedRefreshWorker).to receive(:perform_async)
        .with(an_instance_of(Integer)).once

      post '/youtube/subscribe-bulk', channels: "@PBSNewsHour\n@CNN\n@nope"
      expect(last_response.status).to eq(200)
      body = last_response.body

      # Brand-new feed → ✓ + pending-fetch hint
      expect(body).to match(/Subscribed:\s*<strong>PBS NewsHour/)
      expect(body).to include('Give the system ~30s')
      # Already-existing-in-catalog feed (CNN added pre-test) → already subscribed
      expect(body).to match(/Already subscribed:\s*<strong>CNN/)
      expect(body).to match(/Not found:\s*<code>@nope/)

      # PBS NewsHour should now be in the user's feeds.
      expect(FeedsStore.find_by_url('https://www.youtube.com/feeds/videos.xml?channel_id=UCnp2WgGyc4VyB9HZeUjjeUw')).not_to be_nil
    end

    it 'does NOT enqueue a refresh when the underlying feed already has content' do
      # Set up: a feed exists in the catalog AND has been fetched already
      # (last_fetched_at set). Another user subscribes — we should add
      # the subscription but skip the refresh-worker enqueue because
      # content is already imported.
      stub_resolver(
        '@PBSNewsHour' => {
          status: :ok, channel_id: 'UCnp2WgGyc4VyB9HZeUjjeUw', title: 'PBS NewsHour',
          feed_url: 'https://www.youtube.com/feeds/videos.xml?channel_id=UCnp2WgGyc4VyB9HZeUjjeUw'
        }
      )
      feed_url = 'https://www.youtube.com/feeds/videos.xml?channel_id=UCnp2WgGyc4VyB9HZeUjjeUw'
      # Use subscriber_id: 2 so user 1 is NOT subscribed yet.
      Database.connection.execute('INSERT OR IGNORE INTO users (id, username, display_name) VALUES (2, ?, ?)',
                                  ['otheruser', 'Other'])
      feed = FeedsStore.add(url: feed_url, title: 'PBS NewsHour', subscriber_id: 2)
      FeedsStore.update(feed['id'], last_fetched_at: '2026-05-14T10:00:00Z')

      expect(FeedRefreshWorker).not_to receive(:perform_async)

      post '/youtube/subscribe-bulk', channels: '@PBSNewsHour'
      body = last_response.body
      expect(body).to match(/Subscribed:\s*<strong>PBS NewsHour/)
      expect(body).not_to include('Give the system ~30s')
    end

    it 'reports an error when the textarea is empty' do
      post '/youtube/subscribe-bulk', channels: ''
      expect(last_response.body).to include('Paste at least one channel handle or URL.')
    end

    it 'caps processing at YOUTUBE_BULK_ADD_MAX lines and surfaces a truncation hint' do
      cap   = TechFeedReader::YOUTUBE_BULK_ADD_MAX
      lines = (1..(cap + 3)).map { |i| "@chan#{i}" }
      stub_resolver(lines.to_h { |l| [l, { status: :not_found, error: 'stub' }] })

      post '/youtube/subscribe-bulk', channels: lines.join("\n")
      expect(last_response.body).to include("#{cap} of #{cap + 3}")
      expect(last_response.body).to include('remainder ignored')
    end

    it 'gracefully handles a resolver :error path (e.g. network failure)' do
      stub_resolver('@boom' => { status: :error, error: 'SocketError: DNS failure' })
      post '/youtube/subscribe-bulk', channels: '@boom'
      expect(last_response.body).to match(/Error:\s*<code>@boom/)
      expect(last_response.body).to include('SocketError')
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
