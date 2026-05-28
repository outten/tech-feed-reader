require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/sports_teams_store'
require_relative '../app/sports_leagues_store'
require_relative '../app/sports_matches_store'
require_relative '../app/sports_standings_store'
require_relative '../app/sports_follows_store'

# STUFF #67 — DB-fallback team detail page. The curated SportsTeams
# Ruby module only ships ~5 teams; every other team (FIFA World Cup
# countries, the rest of the NFL/NBA, etc.) used to 404 when clicked
# from a league standings table. The route now falls back to
# SportsTeamsStore.find_by_slug and renders views/sports_team_db.erb.

RSpec.describe 'GET /sports/team/:slug — DB fallback (STUFF #67)' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  def build_db_team(slug:, name:, league_slug: 'fifa-world', league_name: 'FIFA World Cup')
    league = SportsLeaguesStore.upsert(slug: league_slug, name: league_name, sport: 'soccer',
                                       source_provider: 'espn', external_id: "soccer/#{league_slug}")
    team   = SportsTeamsStore.upsert(league_id: league['id'], slug: slug, name: name,
                                     short_name: name.split.first, source_provider: 'espn',
                                     external_id: slug, image_url: "https://logo.example/#{slug}.png")
    [league, team]
  end

  it 'renders a 200 with the team header for a DB-only team' do
    _league, team = build_db_team(slug: 'brazil-mens-national-team', name: 'Brazil')
    get "/sports/team/#{team['slug']}"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Brazil')
    expect(last_response.body).to include('FIFA World Cup')
    expect(last_response.body).to include('sports-team-header')
  end

  it 'shows the empty-state copy when the team has no fixtures, results, or mentions' do
    _league, team = build_db_team(slug: 'usa-mens-national-team', name: 'USA')
    get "/sports/team/#{team['slug']}"
    expect(last_response.body).to include('No fixtures, results, or articles')
  end

  it 'renders upcoming fixtures when sports_matches has rows for the team' do
    league, team = build_db_team(slug: 'germany-mens-national-team', name: 'Germany')
    opponent = SportsTeamsStore.upsert(league_id: league['id'], slug: 'france-mens-national-team',
                                       name: 'France', short_name: 'France',
                                       source_provider: 'espn', external_id: 'france-mens')
    SportsMatchesStore.upsert(league_id: league['id'], source_provider: 'espn',
                              external_id: 'upcoming-001',
                              scheduled_at: (Time.now.utc + 86_400).iso8601,
                              status: 'scheduled',
                              home_team_id: team['id'], away_team_id: opponent['id'],
                              venue: 'Berlin Arena')
    get "/sports/team/#{team['slug']}"
    expect(last_response.body).to include('Upcoming fixtures')
    expect(last_response.body).to include('France')
    expect(last_response.body).to include('Berlin Arena')
  end

  it 'renders recent results when a final exists' do
    league, team = build_db_team(slug: 'argentina-mens-national-team', name: 'Argentina')
    opponent = SportsTeamsStore.upsert(league_id: league['id'], slug: 'chile-mens-national-team',
                                       name: 'Chile', short_name: 'Chile',
                                       source_provider: 'espn', external_id: 'chile-mens')
    SportsMatchesStore.upsert(league_id: league['id'], source_provider: 'espn',
                              external_id: 'final-001',
                              scheduled_at: (Time.now.utc - 86_400).iso8601,
                              status: 'final',
                              home_team_id: team['id'], away_team_id: opponent['id'],
                              home_score: 3, away_score: 1)
    get "/sports/team/#{team['slug']}"
    expect(last_response.body).to include('Recent results')
    expect(last_response.body).to include('Chile')
  end

  it '404s on an unknown slug (neither curated nor DB)' do
    get '/sports/team/this-team-does-not-exist'
    expect(last_response.status).to eq(404)
  end

  it 'still renders the curated page for a Ruby-module team (regression guard)' do
    # `eagles` is in SportsTeams::TEAMS — the route should NOT fall
    # through to the DB path for it, even if there's no sports_teams
    # DB row.
    get '/sports/team/eagles'
    expect(last_response.status).to eq(200)
    # The curated template carries the hand-written blurb; the DB
    # template doesn't. Presence of the blurb is the canary.
    expect(last_response.body).to include('Bleeding Green Nation')
  end
end
