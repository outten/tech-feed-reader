require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/radio_catalog'
require_relative '../app/radio_store'

RSpec.describe 'Internet Radio' do
  include Rack::Test::Methods

  def app = TechFeedReader

  def signed_in(uid = 1, &block)
    yield({ 'rack.session' => { user_id: uid } })
  end

  before { RadioStore.seed_catalog! }

  # ── RadioCatalog ───────────────────────────────────────────────────────────

  describe 'RadioCatalog' do
    it 'has at least 15 stations' do
      expect(RadioCatalog::STATIONS.length).to be >= 15
    end

    it 'every station has required fields' do
      RadioCatalog::STATIONS.each do |s|
        expect(s[:name].to_s).not_to be_empty
        expect(s[:stream_url]).to start_with('https://')
        expect(s[:catalog].to_s).not_to be_empty
      end
    end

    it 'stream_urls are unique' do
      urls = RadioCatalog::STATIONS.map { |s| s[:stream_url] }
      expect(urls.uniq.length).to eq(urls.length)
    end

    it 'groups include SomaFM and Public Radio' do
      expect(RadioCatalog::GROUPS).to include('SomaFM', 'Public Radio')
    end

    it 'by_group returns stations keyed by catalog name' do
      g = RadioCatalog.by_group
      expect(g['SomaFM'].map { |s| s[:name] }).to include('Groove Salad', 'DEF CON Radio')
      expect(g['Public Radio'].map { |s| s[:name] }).to include('KCRW', 'KEXP', 'WFMU')
    end
  end

  # ── RadioStore ─────────────────────────────────────────────────────────────

  describe 'RadioStore' do
    it 'seed_catalog! is idempotent' do
      count_before = RadioStore.all_stations.length
      RadioStore.seed_catalog!
      expect(RadioStore.all_stations.length).to eq(count_before)
    end

    it 'follow! and following? work together' do
      station = RadioStore.all_stations.first
      RadioStore.follow!(1, station['id'])
      expect(RadioStore.following?(1, station['id'])).to be true
    end

    it 'unfollow! removes the follow' do
      station = RadioStore.all_stations.first
      RadioStore.follow!(1, station['id'])
      RadioStore.unfollow!(1, station['id'])
      expect(RadioStore.following?(1, station['id'])).to be false
    end

    it 'follow! is idempotent (ON CONFLICT DO NOTHING)' do
      station = RadioStore.all_stations.first
      RadioStore.follow!(1, station['id'])
      expect { RadioStore.follow!(1, station['id']) }.not_to raise_error
    end

    it 'followed_stations returns only the user\'s followed stations' do
      stations = RadioStore.all_stations.first(2)
      RadioStore.follow!(1, stations[0]['id'])
      followed = RadioStore.followed_stations(1)
      expect(followed.map { |s| s['id'] }).to include(stations[0]['id'])
      expect(followed.map { |s| s['id'] }).not_to include(stations[1]['id'])
    end
  end

  # ── routes ─────────────────────────────────────────────────────────────────

  describe 'GET /radio' do
    it 'renders the radio page with My Stations and Browse Catalog' do
      signed_in { |env| get '/radio', {}, env }
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('Internet Radio')
      expect(last_response.body).to include('My Stations')
      expect(last_response.body).to include('Browse Catalog')
    end

    it 'shows the empty state when no stations are followed' do
      signed_in { |env| get '/radio', {}, env }
      expect(last_response.body).to include("haven't followed any stations")
    end

    it 'shows followed stations in My Stations after following' do
      station = RadioStore.all_stations.first
      RadioStore.follow!(1, station['id'])
      signed_in { |env| get '/radio', {}, env }
      expect(last_response.body).to include(station['name'])
    end

    it 'shows all catalog groups' do
      signed_in { |env| get '/radio', {}, env }
      RadioCatalog::GROUPS.each do |group|
        expect(last_response.body).to include(group)
      end
    end

    it 'shows play buttons for each station' do
      signed_in { |env| get '/radio', {}, env }
      expect(last_response.body).to include('radio-play-btn')
    end
  end

  describe 'POST /radio/follow' do
    it 'follows a station and returns ok: true' do
      station = RadioStore.all_stations.first
      signed_in do |env|
        post '/radio/follow', { station_id: station['id'] }, env
      end
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body['ok']).to be true
      expect(body['following']).to be true
      expect(RadioStore.following?(1, station['id'])).to be true
    end

    it 'returns 404 for an unknown station_id' do
      signed_in do |env|
        post '/radio/follow', { station_id: 999999 }, env
      end
      expect(last_response.status).to eq(404)
    end
  end

  describe 'POST /radio/unfollow' do
    it 'unfollows a station and returns ok: true' do
      station = RadioStore.all_stations.first
      RadioStore.follow!(1, station['id'])
      signed_in do |env|
        post '/radio/unfollow', { station_id: station['id'] }, env
      end
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body['ok']).to be true
      expect(body['following']).to be false
      expect(RadioStore.following?(1, station['id'])).to be false
    end
  end

  describe 'nav' do
    it 'shows Radio link in Browse dropdown for signed-in users' do
      signed_in { |env| get '/radio', {}, env }
      expect(last_response.body).to include('href="/radio"')
    end
  end
end
