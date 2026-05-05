require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'

RSpec.describe 'GET /bus' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  def add_episode(uid:, title:, duration_seconds:, audio: true, hours_ago: 1)
    feed = FeedsStore.find_by_url('https://x.com/podfeed') ||
           FeedsStore.add(url: 'https://x.com/podfeed', title: 'Pod Show')
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: uid, title: title, url: "https://x.com/#{uid}",
      author: nil,
      published_at: (Time.now.utc - hours_ago * 3600).iso8601,
      content_html: '<p>x</p>', content_text: 'x',
      audio_url:              audio ? "https://cdn.example.com/#{uid}.mp3" : nil,
      audio_mime_type:        audio ? 'audio/mpeg' : nil,
      audio_duration_seconds: duration_seconds
    }])
  end

  describe 'filtering' do
    it 'returns episodes <= 15 minutes by default and excludes longer ones' do
      add_episode(uid: 'short001', title: '10-min show',         duration_seconds: 600)
      add_episode(uid: 'border15', title: 'right-at-cutoff',     duration_seconds: 900)
      add_episode(uid: 'long0001', title: '30-min show',         duration_seconds: 1800)
      add_episode(uid: 'massive1', title: '2-hour deep dive',    duration_seconds: 7200)

      get '/bus'
      expect(last_response.status).to eq(200)
      body = last_response.body
      expect(body).to include('10-min show')
      expect(body).to include('right-at-cutoff')
      expect(body).not_to include('30-min show')
      expect(body).not_to include('2-hour deep dive')
    end

    it 'omits articles that have no audio_url even if their duration is short' do
      add_episode(uid: 'noaudioar', title: 'plain article', duration_seconds: 300, audio: false)
      get '/bus'
      expect(last_response.body).not_to include('plain article')
    end

    it 'omits podcast episodes whose audio_duration_seconds is unknown (NULL)' do
      add_episode(uid: 'noduration1', title: 'duration-less',
                  duration_seconds: nil)
      get '/bus'
      expect(last_response.body).not_to include('duration-less')
    end

    it 'orders newest published first' do
      add_episode(uid: 'older0001', title: 'older episode', duration_seconds: 600, hours_ago: 24)
      add_episode(uid: 'newer0001', title: 'newer episode', duration_seconds: 600, hours_ago: 1)

      get '/bus'
      newer_at = last_response.body.index('newer episode')
      older_at = last_response.body.index('older episode')
      expect(newer_at).to be < older_at
    end
  end

  describe 'cutoff control' do
    it 'honours ?max_minutes=N when N is a positive integer' do
      add_episode(uid: 'short9999', title: 'eight-min show', duration_seconds: 8 * 60)
      add_episode(uid: 'medium999', title: 'twenty-min show', duration_seconds: 20 * 60)

      get '/bus?max_minutes=10'
      expect(last_response.body).to include('eight-min show')
      expect(last_response.body).not_to include('twenty-min show')

      get '/bus?max_minutes=25'
      expect(last_response.body).to include('eight-min show')
      expect(last_response.body).to include('twenty-min show')
    end

    it 'falls back to the default when ?max_minutes is non-numeric' do
      get '/bus?max_minutes=spaceship'
      expect(last_response.body).to include('≤ 15 minutes')
    end

    it 'clamps a wildly large ?max_minutes to BUS_MAX_MINUTES_LIMIT' do
      get '/bus?max_minutes=99999'
      cutoff_label = last_response.body[/&le;\s*(\d+)\s*minutes/, 1]
      expect(cutoff_label.to_i).to be <= TechFeedReader::BUS_MAX_MINUTES_LIMIT
    end
  end

  describe 'header surface' do
    it 'renders the bus icon link in the header on every layout-rendered page' do
      get '/dashboard'
      expect(last_response.body).to include('href="/bus"')
      expect(last_response.body).to include('Bus mode')
    end

    it 'marks the bus icon as active when on /bus' do
      get '/bus'
      expect(last_response.body).to match(/href="\/bus"[^>]*class="[^"]*active/)
    end
  end

  describe 'empty state' do
    it 'renders an empty-state notice when no episodes match the cutoff' do
      add_episode(uid: 'longest01', title: '3-hour show', duration_seconds: 3 * 3600)
      get '/bus'
      expect(last_response.body).to include('No podcast episodes under')
    end
  end
end

RSpec.describe ArticlesStore, '.recent with max_duration_seconds' do
  def add(uid, duration_seconds, audio: true)
    feed = FeedsStore.find_by_url('https://x.com/feed') ||
           FeedsStore.add(url: 'https://x.com/feed', title: 'Feed')
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: uid, title: uid, url: "https://x.com/#{uid}", author: nil,
      published_at: '2026-05-05T12:00:00Z',
      content_html: '<p>x</p>', content_text: 'x',
      audio_url:              audio ? 'https://example.com/a.mp3' : nil,
      audio_mime_type:        audio ? 'audio/mpeg' : nil,
      audio_duration_seconds: duration_seconds
    }])
  end

  it 'limits to articles whose audio_duration_seconds is non-NULL and ≤ the cutoff' do
    # In practice audio_duration_seconds is only ever set on rows that
    # also have audio_url (parsed together from itunes:duration on the
    # enclosure entry). The duration filter is purely on duration —
    # callers that want "podcasts only" pair it with kind: :podcast,
    # which is what /bus does.
    add('shortmin0001', 300)
    add('atcutoffsec1', 600)
    add('justoversec1', 601)
    add('noduration11', nil)

    rows = ArticlesStore.recent(limit: 25, max_duration_seconds: 600)
    titles = rows.map { |r| r['title'] }
    expect(titles).to contain_exactly('shortmin0001', 'atcutoffsec1')
  end

  it 'composes with kind: :podcast — duration cutoff plus audio_url IS NOT NULL' do
    add('podshortma1',  300, audio: true)
    add('podlong00001', 1800, audio: true)
    add('plainshortwd', 300, audio: false)  # data-integrity outlier; should still get filtered

    rows = ArticlesStore.recent(limit: 25, kind: :podcast, max_duration_seconds: 600)
    titles = rows.map { |r| r['title'] }
    expect(titles).to contain_exactly('podshortma1')
  end
end
