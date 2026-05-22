require_relative 'spec_helper'
require_relative '../app/main'

# STUFF #52.1 — clicking a notable-player chip on a team card upserts
# the catalog player into sports_players on first hit. Spec covers
# the slug computation, the upsert idempotence, and the GET
# /sports/player/:slug route's catalog fallback for unknown slugs.
RSpec.describe 'Catalog player upsert (STUFF #52.1)' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  let(:eagles_player) { 'Jalen Hurts' }
  let(:eagles_slug)   { 'eagles' }
  # The chip-link href is computed by TechFeedReader#catalog_player_slug.
  let(:expected_slug) { 'eagles-jalen-hurts' }

  describe 'GET /sports/player/:slug' do
    before do
      # Make sure we start without the DB row, so the route exercises
      # the catalog fallback fresh.
      existing = SportsPlayersStore.find_by_slug(expected_slug)
      Database.exec('DELETE FROM sports_players WHERE id = ?', [existing['id']]) if existing
    end

    it 'upserts a catalog player into sports_players on first hit and serves the page' do
      expect(SportsPlayersStore.find_by_slug(expected_slug)).to be_nil

      get "/sports/player/#{expected_slug}"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include(eagles_player)

      row = SportsPlayersStore.find_by_slug(expected_slug)
      expect(row).not_to be_nil
      expect(row['full_name']).to eq(eagles_player)
      expect(row['source_provider']).to eq('catalog')
      expect(row['external_id']).to eq(expected_slug)
      expect(row['sport']).to eq('football')
    end

    it 'is idempotent — second hit reuses the row instead of duplicating' do
      get "/sports/player/#{expected_slug}"
      first  = SportsPlayersStore.find_by_slug(expected_slug)

      get "/sports/player/#{expected_slug}"
      second = SportsPlayersStore.find_by_slug(expected_slug)
      expect(second['id']).to eq(first['id'])
    end

    it 'surfaces the back-link to the team page (no tennis-specific UI)' do
      get "/sports/player/#{expected_slug}"
      expect(last_response.body).to include('Notable player on')
      expect(last_response.body).to include('Philadelphia Eagles')
      expect(last_response.body).to include('/sports/manage/football/nfl')
      # No tennis-specific chrome
      expect(last_response.body).not_to include('All rankings')
      expect(last_response.body).not_to include('Open on ESPN')
      expect(last_response.body).not_to include('Tour ranking points')
    end

    it '404s for a slug whose team prefix exists but player name does not' do
      get "/sports/player/#{eagles_slug}-no-such-player"
      expect(last_response.status).to eq(404)
    end

    it '404s for a slug whose prefix does not match any catalog team' do
      get '/sports/player/nonexistent-team-someone'
      expect(last_response.status).to eq(404)
    end
  end

  describe 'slugify helper' do
    let(:instance) { TechFeedReader.new! }

    it 'strips accents (so Mbappé → mbappe)' do
      expect(instance.send(:slugify, 'Kylian Mbappé')).to eq('kylian-mbappe')
    end

    it 'collapses runs of non-alphanumerics + trims edges' do
      expect(instance.send(:slugify, '  A.J. Brown  ')).to eq('a-j-brown')
    end
  end

  describe 'chip render on /sports/manage/<sport>/<league>' do
    it 'wraps each notable-player name in a link to /sports/player/<slug>' do
      get '/sports/manage/football/nfl'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include(%(href="/sports/player/#{expected_slug}"))
      expect(last_response.body).to include(eagles_player)
    end
  end
end
