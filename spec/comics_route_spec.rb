require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'

# STUFF #65 — webcomics index page. Mirrors /podcasts in shape but
# filters by `feeds.topic = 'humor'` instead of audio_url presence.
RSpec.describe 'GET /comics' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  def subscribe_comic_feed(url:, title:)
    FeedsStore.add(url: url, title: title, topic: 'humor', subscriber_id: 1)
  end

  it 'renders the empty state when no humor feeds are subscribed' do
    get '/comics'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('No webcomics subscribed yet')
    expect(last_response.body).to include('/feeds')
  end

  it 'lists subscribed series with panel counts and recent panels' do
    feed = subscribe_comic_feed(url: 'https://xkcd.example/atom.xml', title: 'xkcd')
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: 'comic_panel01', title: 'Standards', url: 'https://xkcd.example/927',
      author: nil, published_at: '2026-05-20T12:00:00Z',
      content_html: '<p><img src="https://xkcd.example/927.png"></p>', content_text: 'Standards',
      image_url: 'https://xkcd.example/927.png'
    }])

    get '/comics'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('xkcd')
    expect(last_response.body).to include('podcast-show-card') # reused tile CSS
    expect(last_response.body).to include('Standards')
    # STUFF #66 — series tile now opens the series archive at
    # /comics/:feed_id (not directly the latest panel article).
    expect(last_response.body).to include(%(href="/comics/#{feed['id']}"))
  end

  it 'shows the source series name on every recent-panels row (STUFF #66)' do
    feed = subscribe_comic_feed(url: 'https://xkcd.example/atom.xml', title: 'xkcd')
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: 'comic_seriesnm', title: 'Geohashing', url: 'https://xkcd.example/426',
      author: nil, published_at: '2026-05-20T12:00:00Z',
      content_html: '<p>x</p>', content_text: 'x'
    }])

    get '/comics'
    # The Recent panels meta line links the series name back to the
    # series archive.
    expect(last_response.body).to match(%r{<a href="/comics/#{feed['id']}">xkcd</a>})
  end

  it 'excludes non-humor feeds even when other content exists' do
    humor = subscribe_comic_feed(url: 'https://smbc.example/rss', title: 'SMBC')
    tech  = FeedsStore.add(url: 'https://ars.example/rss', title: 'Ars', topic: 'technology', subscriber_id: 1)
    ArticlesStore.import(feed_id: humor['id'], entries: [{
      uid: 'humor_panel01', title: 'Philosophy joke', url: 'https://smbc.example/x',
      author: nil, published_at: '2026-05-20T08:00:00Z',
      content_html: '<p>x</p>', content_text: 'x'
    }])
    ArticlesStore.import(feed_id: tech['id'], entries: [{
      uid: 'tech_post001', title: 'Ars post', url: 'https://ars.example/x',
      author: nil, published_at: '2026-05-20T09:00:00Z',
      content_html: '<p>x</p>', content_text: 'x'
    }])

    get '/comics'
    expect(last_response.body).to include('SMBC')
    expect(last_response.body).not_to include('Ars post') # tech article shouldn't leak in
  end

  it 'exposes Comics in the main nav under Browse' do
    get '/admin/dashboard'
    expect(last_response.body).to include('href="/comics"')
    expect(last_response.body).to include('Browse')
  end
end

RSpec.describe 'GET /comics/:feed_id' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  def subscribe_comic_feed(url:, title:)
    FeedsStore.add(url: url, title: title, topic: 'humor', subscriber_id: 1)
  end

  it 'lists the recent panels for the series with thumbnails + per-panel links' do
    feed = subscribe_comic_feed(url: 'https://xkcd.example/atom.xml', title: 'xkcd')
    ArticlesStore.import(feed_id: feed['id'], entries: [
      { uid: 'series_pn001', title: 'Standards',  url: 'https://xkcd.example/927',
        author: nil, published_at: '2026-05-20T12:00:00Z',
        content_html: '<p>x</p>', content_text: 'Standards',
        image_url: 'https://xkcd.example/927.png' },
      { uid: 'series_pn002', title: 'Geohashing', url: 'https://xkcd.example/426',
        author: nil, published_at: '2026-05-18T12:00:00Z',
        content_html: '<p>x</p>', content_text: 'Geohashing',
        image_url: 'https://xkcd.example/426.png' }
    ])

    get "/comics/#{feed['id']}"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('xkcd')
    expect(last_response.body).to include('Standards')
    expect(last_response.body).to include('Geohashing')
    expect(last_response.body).to include('/article/series_pn001')
    expect(last_response.body).to include('/article/series_pn002')
    expect(last_response.body).to include('All series')
  end

  it 'renders the empty-state when no panels exist yet' do
    feed = subscribe_comic_feed(url: 'https://xkcd.example/atom.xml', title: 'xkcd')
    get "/comics/#{feed['id']}"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('No panels ingested for this series yet')
  end

  it '404s for a non-humor feed even when subscribed' do
    tech = FeedsStore.add(url: 'https://ars.example/rss', title: 'Ars',
                          topic: 'technology', subscriber_id: 1)
    get "/comics/#{tech['id']}"
    expect(last_response.status).to eq(404)
  end

  it '404s for a humor feed the user is not subscribed to' do
    # add_to_catalog creates a catalog row without subscribing the
    # default test user — same shape another user's subscription
    # would have left behind.
    foreign = FeedsStore.add_to_catalog(url: 'https://other.example/rss',
                                        title: 'Other', topic: 'humor')
    get "/comics/#{foreign['id']}"
    expect(last_response.status).to eq(404)
  end

  it '404s for a non-existent feed id' do
    get '/comics/999999'
    expect(last_response.status).to eq(404)
  end
end

RSpec.describe ArticlesStore, '.comic_feeds' do
  it 'returns one row per humor-topic feed in the user\'s subscriptions, ordered by latest' do
    older = FeedsStore.add(url: 'https://older.example/rss', title: 'Older Comic', topic: 'humor', subscriber_id: 1)
    newer = FeedsStore.add(url: 'https://newer.example/rss', title: 'Newer Comic', topic: 'humor', subscriber_id: 1)
    ArticlesStore.import(feed_id: older['id'], entries: [{
      uid: 'older_panel01', title: 'Old panel', url: 'https://older.example/1',
      author: nil, published_at: '2026-05-10T00:00:00Z',
      content_html: '<p>x</p>', content_text: 'x'
    }])
    ArticlesStore.import(feed_id: newer['id'], entries: [{
      uid: 'newer_panel01', title: 'New panel', url: 'https://newer.example/1',
      author: nil, published_at: '2026-05-25T00:00:00Z',
      content_html: '<p>x</p>', content_text: 'x'
    }])

    rows = ArticlesStore.comic_feeds(1)
    expect(rows.length).to eq(2)
    expect(rows.first['title']).to eq('Newer Comic')
    expect(rows.first['latest_uid']).to eq('newer_panel01')
    expect(rows.first['panel_count']).to eq(1)
  end

  it 'excludes feeds without humor topic' do
    FeedsStore.add(url: 'https://tech.example/rss', title: 'Tech', topic: 'technology', subscriber_id: 1)
    expect(ArticlesStore.comic_feeds(1)).to be_empty
  end
end
