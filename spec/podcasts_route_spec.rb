require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/feed_parser'

RSpec.describe 'GET /podcasts' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  let(:body) { File.read(File.expand_path('fixtures/podcast_rss.xml', __dir__)) }

  def import_podcast_feed
    feed   = FeedsStore.add(url: 'https://example.com/podcast/feed', title: 'Test Podcast Show')
    parsed = FeedParser.parse(body, feed_url: feed['url'])
    ArticlesStore.import(feed_id: feed['id'], entries: parsed[:entries])
    feed
  end

  it 'renders the empty state when no podcast feeds have episodes' do
    get '/podcasts'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('No podcasts subscribed yet')
    expect(last_response.body).to include('/feeds')
  end

  it 'lists subscribed shows with episode counts and recent episodes' do
    feed = import_podcast_feed
    get '/podcasts'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Test Podcast Show')
    expect(last_response.body).to include('podcast-show-card')
    expect(last_response.body).to include('podcast-card')
    expect(last_response.body).to include('Episode 12 — On Building Things')
    expect(last_response.body).to include('1:23:45')           # hh:mm:ss duration
    expect(last_response.body).to include('▶ Listen')
    expect(last_response.body).to include("/articles?feed_id=#{feed['id']}&kind=podcast")
  end

  it 'omits the duration span when the entry had no itunes:duration' do
    feed = FeedsStore.add(url: 'https://example.com/feed.rss', title: 'Mystery show')
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: 'durmissing12', title: 'Surprise', url: 'https://example.com/x',
      author: nil, published_at: '2026-05-02T12:00:00Z',
      content_html: '<p>x</p>', content_text: 'x',
      audio_url: 'https://cdn.example.com/x.mp3', audio_mime_type: 'audio/mpeg',
      audio_duration_seconds: nil
    }])
    get '/podcasts'
    expect(last_response.body).to include('Mystery show')
    expect(last_response.body).not_to include('podcast-card-duration')
  end

  it 'exposes Podcasts in the main nav' do
    get '/admin/dashboard'
    expect(last_response.body).to include('href="/podcasts"')
  end
end

RSpec.describe 'GET /articles ?kind=podcast' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  let(:body) { File.read(File.expand_path('fixtures/podcast_rss.xml', __dir__)) }

  it 'narrows the list to podcast episodes only' do
    podcast_feed = FeedsStore.add(url: 'https://example.com/podcast/feed', title: 'Pod')
    parsed       = FeedParser.parse(body, feed_url: podcast_feed['url'])
    ArticlesStore.import(feed_id: podcast_feed['id'], entries: parsed[:entries])

    plain_feed = FeedsStore.add(url: 'https://example.com/blog.rss', title: 'Plain')
    ArticlesStore.import(feed_id: plain_feed['id'], entries: [{
      uid: 'plainpost123', title: 'A blog post', url: 'https://example.com/p',
      author: nil, published_at: '2026-05-02T12:00:00Z',
      content_html: '<p>x</p>', content_text: 'x'
    }])

    get '/articles?kind=podcast'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Episode 12')
    expect(last_response.body).not_to include('A blog post')
    expect(last_response.body).to include('podcasts only')   # filter UI active
    expect(last_response.body).to include('show all')
  end
end

RSpec.describe 'ArticlesStore podcast helpers' do
  let(:body) { File.read(File.expand_path('fixtures/podcast_rss.xml', __dir__)) }

  it '.podcast_feeds returns one row per podcast feed with episode count' do
    feed   = FeedsStore.add(url: 'https://example.com/podcast/feed', title: 'Pod')
    parsed = FeedParser.parse(body, feed_url: feed['url'])
    ArticlesStore.import(feed_id: feed['id'], entries: parsed[:entries])

    rows = ArticlesStore.podcast_feeds(1)
    expect(rows.length).to eq(1)
    expect(rows.first['title']).to eq('Pod')
    expect(rows.first['episode_count']).to eq(3)   # 3 of 4 entries have audio_url
  end

  it '.recent(kind: :podcast) excludes non-podcast articles' do
    feed = FeedsStore.add(url: 'https://example.com/mixed.rss', title: 'Mixed')
    ArticlesStore.import(feed_id: feed['id'], entries: [
      { uid: 'plain0000001', title: 'plain', url: 'https://example.com/a',
        author: nil, published_at: '2026-05-02T12:00:00Z',
        content_html: '<p>x</p>', content_text: 'x' },
      { uid: 'audio0000002', title: 'audio', url: 'https://example.com/b',
        author: nil, published_at: '2026-05-02T13:00:00Z',
        content_html: '<p>y</p>', content_text: 'y',
        audio_url: 'https://cdn.example.com/x.mp3',
        audio_mime_type: 'audio/mpeg', audio_duration_seconds: 1234 }
    ])
    titles = ArticlesStore.recent(1, kind: :podcast).map { |a| a['title'] }
    expect(titles).to eq(['audio'])
  end
end
