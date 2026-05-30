require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/sports_leagues_store'
require_relative '../app/sports_teams_store'
require_relative '../app/sports_matches_store'

# STUFF #70 follow-up — /sports/league/:slug now surfaces fixtures
# and results below the standings table. Previously the matches
# pulled by SportsSync.sync_followed_league_events! lived in the DB
# but nothing in the UI rendered them.

RSpec.describe SportsMatchesStore, '.upcoming_for_league + .recent_finals_for_league (STUFF #70 follow-up)' do
  let(:now) { Time.parse('2026-06-01T00:00Z').utc }

  def make_league_match(league, *args)
    home = SportsTeamsStore.upsert(league_id: league['id'], slug: "home-#{args[0]}",
                                    name: 'Home', source_provider: 'espn', external_id: "h#{args[0]}")
    away = SportsTeamsStore.upsert(league_id: league['id'], slug: "away-#{args[0]}",
                                    name: 'Away', source_provider: 'espn', external_id: "a#{args[0]}")
    SportsMatchesStore.upsert(
      league_id: league['id'], source_provider: 'espn',
      external_id: "evt-#{args[0]}",
      scheduled_at: args[1], status: args[2],
      home_team_id: home['id'], away_team_id: away['id'],
      home_score: args[3], away_score: args[4], venue: 'Estadio Test'
    )
  end

  let(:league) do
    SportsLeaguesStore.upsert(slug: 'fifa-world', name: 'FIFA World Cup', sport: 'soccer',
                              source_provider: 'espn', external_id: 'soccer/fifa.world')
  end

  it 'upcoming_for_league returns scheduled + live matches in the league, soonest first' do
    make_league_match(league, 'A', '2026-06-12T18:00Z', 'scheduled')
    make_league_match(league, 'B', '2026-06-11T18:00Z', 'scheduled')   # earlier
    make_league_match(league, 'C', '2026-05-20T18:00Z', 'final', 2, 1) # past + final → excluded

    rows = SportsMatchesStore.upcoming_for_league(league['id'], now: now)
    expect(rows.map { |r| r['external_id'] }).to eq(%w[evt-B evt-A])
  end

  it 'recent_finals_for_league returns only finals, newest first' do
    make_league_match(league, 'A', '2026-05-20T18:00Z', 'final', 2, 1)
    make_league_match(league, 'B', '2026-05-22T18:00Z', 'final', 3, 0)
    make_league_match(league, 'C', '2026-06-12T18:00Z', 'scheduled')

    rows = SportsMatchesStore.recent_finals_for_league(league['id'])
    expect(rows.map { |r| r['external_id'] }).to eq(%w[evt-B evt-A])
  end

  it 'scopes both lookups to the requested league' do
    other = SportsLeaguesStore.upsert(slug: 'uefa-euro', name: 'UEFA Euro', sport: 'soccer',
                                       source_provider: 'espn', external_id: 'soccer/uefa.euro')
    make_league_match(league, 'A', '2026-06-12T18:00Z', 'scheduled')
    make_league_match(other,  'B', '2026-06-12T18:00Z', 'scheduled')

    expect(SportsMatchesStore.upcoming_for_league(league['id'], now: now).length).to eq(1)
    expect(SportsMatchesStore.upcoming_for_league(other['id'], now: now).length).to eq(1)
  end
end

RSpec.describe 'GET /sports/league/:slug — fixtures + results (STUFF #70 follow-up)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'renders Upcoming fixtures + Recent results sections when matches exist' do
    league = SportsLeaguesStore.upsert(slug: 'fifa-world', name: 'FIFA World Cup',
                                       sport: 'soccer', source_provider: 'espn',
                                       external_id: 'soccer/fifa.world')
    home = SportsTeamsStore.upsert(league_id: league['id'], slug: 'mexico', name: 'Mexico',
                                    source_provider: 'espn', external_id: 'mx')
    away = SportsTeamsStore.upsert(league_id: league['id'], slug: 'south-africa', name: 'South Africa',
                                    source_provider: 'espn', external_id: 'za')
    SportsMatchesStore.upsert(
      league_id: league['id'], source_provider: 'espn', external_id: 'evt-up',
      scheduled_at: (Time.now.utc + 86_400).iso8601, status: 'scheduled',
      home_team_id: home['id'], away_team_id: away['id'], venue: 'Estadio Banorte'
    )
    SportsMatchesStore.upsert(
      league_id: league['id'], source_provider: 'espn', external_id: 'evt-fn',
      scheduled_at: (Time.now.utc - 86_400).iso8601, status: 'final',
      home_team_id: home['id'], away_team_id: away['id'],
      home_score: 2, away_score: 1
    )

    get '/sports/league/fifa-world'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Upcoming fixtures')
    expect(last_response.body).to include('Recent results')
    expect(last_response.body).to include('Mexico')
    expect(last_response.body).to include('South Africa')
    expect(last_response.body).to include('Estadio Banorte')
  end

  it 'renders the empty-state for a catalog-source tournament with nothing synced' do
    SportsLeaguesStore.upsert(slug: 'roland-garros', name: 'Roland Garros',
                              sport: 'tennis', source_provider: 'catalog',
                              external_id: 'roland-garros')

    get '/sports/league/roland-garros'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('No live data synced')
    expect(last_response.body).to include("doesn't have a live-data provider")
  end

  it 'renders the empty-state for an ESPN league with no synced data yet' do
    SportsLeaguesStore.upsert(slug: 'uefa-euro', name: 'UEFA Euro', sport: 'soccer',
                              source_provider: 'espn', external_id: 'soccer/uefa.euro')

    get '/sports/league/uefa-euro'
    expect(last_response.body).to include('No live data synced')
    expect(last_response.body).to include('make sync-sports')
  end
end
