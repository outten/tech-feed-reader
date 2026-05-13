require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/read_state_store'

# Phase 2 polish (2026-05-12) — "Pick up where you left off" tile.
# Position state lives in localStorage (client-side only); the
# server-side surface is just a lookup endpoint + a placeholder
# slot in the home view's returning-user branch. The full render
# happens in public/continue-progress.js.

RSpec.describe 'GET /api/articles/lookup' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  def seed(uid:, title:, audio_url: nil, duration: nil, url: nil)
    feed = FeedsStore.find_by_url('https://example.com/lookup') ||
           FeedsStore.add(url: 'https://example.com/lookup', title: 'Lookup Feed')
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: uid, title: title,
      url: url || "https://example.com/#{uid}", author: nil,
      published_at: '2026-05-10T12:00:00Z',
      content_html: '<p>x</p>', content_text: 'x',
      audio_url: audio_url, audio_mime_type: nil,
      audio_duration_seconds: duration
    }])
    ArticlesStore.find_by_uid(uid)
  end

  it 'returns the article metadata for valid uids' do
    seed(uid: 'lookup_pod001', title: 'Pod ep',
         audio_url: 'https://example.com/p.mp3', duration: 1200)
    get '/api/articles/lookup?uids=lookup_pod001'
    expect(last_response.status).to eq(200)
    body = JSON.parse(last_response.body)
    expect(body['articles'].length).to eq(1)
    row = body['articles'].first
    expect(row['uid']).to eq('lookup_pod001')
    expect(row['title']).to eq('Pod ep')
    expect(row['audio_url']).to eq('https://example.com/p.mp3')
    expect(row['audio_duration_seconds']).to eq(1200)
    expect(row['feed_title']).to eq('Lookup Feed')
  end

  it 'silently drops unknown uids' do
    seed(uid: 'lookup_real01', title: 'Real')
    get '/api/articles/lookup?uids=lookup_real01,does_not_exist'
    body = JSON.parse(last_response.body)
    expect(body['articles'].map { |r| r['uid'] }).to eq(['lookup_real01'])
  end

  it 'returns an empty list when uids param is missing or blank' do
    get '/api/articles/lookup'
    expect(JSON.parse(last_response.body)).to eq('articles' => [])

    get '/api/articles/lookup?uids='
    expect(JSON.parse(last_response.body)).to eq('articles' => [])
  end

  it 'caps the lookup at 20 uids' do
    25.times { |i| seed(uid: "lookcap0#{i.to_s.rjust(4, '0')}", title: "T#{i}") }
    uids = 25.times.map { |i| "lookcap0#{i.to_s.rjust(4, '0')}" }.join(',')
    get "/api/articles/lookup?uids=#{uids}"
    expect(JSON.parse(last_response.body)['articles'].length).to be <= 20
  end
end

RSpec.describe 'GET / — Continue progress slot (returning user)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  def seed_returning!
    feed = FeedsStore.find_by_url('https://example.com/continue-sentinel') ||
           FeedsStore.add(url: 'https://example.com/continue-sentinel', title: 'Sentinel')
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: 'continue_sentinel', title: 'A',
      url: 'https://example.com/a', author: nil,
      published_at: '2000-01-01T00:00:00Z',
      content_html: '<p>x</p>', content_text: 'x',
      audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
    }])
    ReadStateStore.mark_bookmarked(ArticlesStore.find_by_uid('continue_sentinel')['id'], value: true)
  end

  it 'renders an empty #continue-progress slot + the JS that fills it' do
    seed_returning!
    get '/'
    expect(last_response.body).to match(%r{<section id="continue-progress"[^>]*hidden})
    expect(last_response.body).to match(%r{<script src="/continue-progress\.js})
  end

  it 'does NOT render the slot or JS for anonymous visitors' do
    get '/'
    expect(last_response.body).not_to include('id="continue-progress"')
    expect(last_response.body).not_to include('continue-progress.js')
  end
end
