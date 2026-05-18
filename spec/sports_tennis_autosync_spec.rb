require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/sports_players_store'
require_relative '../app/providers/espn'

# STUFF #46 — opportunistic ESPN refresh on /sports/tennis page load.
# Covers: TTL gating (no refresh when fresh), refresh when stale or
# empty, helper extraction (tennis_player_slug + refresh!), and the
# route's ?skip_refresh=1 bypass.
RSpec.describe 'SportsPlayersStore tennis autosync (STUFF #46)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  describe '.tennis_player_slug' do
    it 'lowercases + ASCII-folds + hyphenates' do
      expect(SportsPlayersStore.tennis_player_slug('Iga Świątek')).to eq('iga-swiatek')
    end

    it 'returns nil for non-alphanumeric-only input' do
      expect(SportsPlayersStore.tennis_player_slug('!!!')).to be_nil
    end

    it 'collapses runs of separators' do
      expect(SportsPlayersStore.tennis_player_slug('Jan-Lennard  Struff')).to eq('jan-lennard-struff')
    end
  end

  describe '.refresh_if_stale!' do
    let(:entry) do
      double('Entry',
        full_name: 'Iga Swiatek', country: 'POL',
        headshot_url: nil, flag_url: nil,
        tour: 'wta', current_rank: 1, previous_rank: 2,
        points: 11000, trend: 'up',
        athlete_external_id: '5031')
    end

    it 'pulls from ESPN + upserts when the table is empty for the tour' do
      expect(Providers::ESPN).to receive(:tennis_rankings).with(tour: 'wta').and_return([entry])
      result = SportsPlayersStore.refresh_if_stale!(tour: 'wta')
      expect(result).to eq(:refreshed)
      expect(SportsPlayersStore.top_ranked(tour: 'wta').first['full_name']).to eq('Iga Swiatek')
    end

    it 'skips the ESPN call when last_synced_at is within the TTL' do
      SportsPlayersStore.upsert(
        sport: 'tennis', slug: 'jannik-sinner', full_name: 'Jannik Sinner',
        source_provider: 'espn', external_id: '4', tour: 'atp', current_rank: 1
      )
      # last_synced_at on the row is now() — definitely within 12h.
      expect(Providers::ESPN).not_to receive(:tennis_rankings)
      expect(SportsPlayersStore.refresh_if_stale!(tour: 'atp')).to eq(:fresh)
    end

    it 'returns 0 (no upsert) when ESPN returns an empty array' do
      expect(Providers::ESPN).to receive(:tennis_rankings).with(tour: 'atp').and_return([])
      SportsPlayersStore.refresh_if_stale!(tour: 'atp')
      expect(SportsPlayersStore.top_ranked(tour: 'atp')).to be_empty
    end
  end

  describe 'GET /sports/tennis' do
    let(:atp_entry) do
      double('Entry',
        full_name: 'Carlos Alcaraz', country: 'ESP',
        headshot_url: nil, flag_url: nil,
        tour: 'atp', current_rank: 1, previous_rank: 1,
        points: 9000, trend: 'flat',
        athlete_external_id: '5009')
    end

    it 'triggers a refresh on each tour when the table is empty' do
      expect(Providers::ESPN).to receive(:tennis_rankings).with(tour: 'atp').and_return([atp_entry])
      expect(Providers::ESPN).to receive(:tennis_rankings).with(tour: 'wta').and_return([])
      get '/sports/tennis'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('Carlos Alcaraz')
    end

    it 'skips the refresh path with ?skip_refresh=1 (debugging hatch)' do
      expect(Providers::ESPN).not_to receive(:tennis_rankings)
      get '/sports/tennis?skip_refresh=1'
      expect(last_response.status).to eq(200)
      # Empty-state copy renders since nothing is in the DB.
      expect(last_response.body).to include('No tennis rankings yet')
    end

    it 'swallows ESPN errors without blowing up the page' do
      allow(Providers::ESPN).to receive(:tennis_rankings).and_raise(StandardError, 'connection refused')
      get '/sports/tennis'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('No tennis rankings yet')
    end
  end
end
