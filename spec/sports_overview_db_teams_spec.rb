require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/sports_teams_store'
require_relative '../app/sports_leagues_store'
require_relative '../app/sports_matches_store'
require_relative '../app/sports_follows_store'

# STUFF #68 — /sports overview also pulls DB-side followed teams
# from sports_follows, not just the curated SportsTeams Ruby module.
# Without this, following the Phillies (or any team outside the
# curated 5 in app/sports_teams.rb) shows no panel on /sports.

RSpec.describe 'GET /sports — DB-followed teams (STUFF #68)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  def seed_db_team(slug:, name:, league_slug: 'mlb', sport: 'baseball', external_id:)
    league = SportsLeaguesStore.upsert(slug: league_slug, name: league_slug.upcase, sport: sport,
                                       source_provider: 'espn', external_id: "#{sport}/#{league_slug}")
    team   = SportsTeamsStore.upsert(league_id: league['id'], slug: slug, name: name,
                                     short_name: name.split.last, source_provider: 'espn',
                                     external_id: external_id, image_url: "https://logo.example/#{slug}.png")
    [league, team]
  end

  def add_final(league:, focal:, opponent_external_id:, focal_score:, opp_score:, focal_is_home: true,
                scheduled_at: '2026-04-01T00:00Z')
    opp = SportsTeamsStore.upsert(league_id: league['id'], slug: "#{focal['slug']}-opp",
                                  name: 'Mets', source_provider: 'espn',
                                  external_id: opponent_external_id,
                                  image_url: 'https://logo.example/opp.png')
    SportsMatchesStore.upsert(
      league_id: league['id'], source_provider: 'espn', external_id: "evt-#{focal['slug']}",
      scheduled_at: scheduled_at, status: 'final',
      home_team_id: focal_is_home ? focal['id'] : opp['id'],
      away_team_id: focal_is_home ? opp['id']   : focal['id'],
      home_score:   focal_is_home ? focal_score : opp_score,
      away_score:   focal_is_home ? opp_score   : focal_score,
      venue:        'Citizens Bank Park'
    )
  end

  it 'renders a score tile for a DB-followed team with a synced final' do
    league, phillies = seed_db_team(slug: 'phillies', name: 'Philadelphia Phillies',
                                    external_id: '22')
    add_final(league: league, focal: phillies, opponent_external_id: '21',
              focal_score: 5, opp_score: 2)
    SportsFollowsStore.add(user_id: 1, kind: 'team', value: 'phillies')

    get '/sports'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('class="sports-score-tiles"')
    expect(last_response.body).to include('Phillies')
    expect(last_response.body).to include('href="/sports/team/phillies"')
  end

  it 'still includes the DB-followed team in the TOC team-button row even without a synced final' do
    _league, _phillies = seed_db_team(slug: 'phillies', name: 'Philadelphia Phillies',
                                      external_id: '22')
    SportsFollowsStore.add(user_id: 1, kind: 'team', value: 'phillies')

    get '/sports'
    expect(last_response.status).to eq(200)
    # No synced final → no score-tile panel, but the TOC team-button
    # row should still link to the team page.
    expect(last_response.body).to include('href="/sports/team/phillies"')
  end

  it 'gracefully skips a followed slug that has no sports_teams row' do
    SportsFollowsStore.add(user_id: 1, kind: 'team', value: 'made-up-team-slug')
    expect { get '/sports' }.not_to raise_error
    expect(last_response.body).not_to include('made-up-team-slug')
  end

  it 'does not duplicate a team that exists in both the curated module and DB follows' do
    # Eagles is in SportsTeams::TEAMS (curated). If a user has both
    # subscribed to a catalog feed AND added a sports_follows row,
    # the team should appear exactly once.
    league, eagles = seed_db_team(slug: 'eagles', name: 'Philadelphia Eagles',
                                  league_slug: 'nfl', sport: 'football', external_id: '21')
    FeedsStore.add(url: 'https://www.bleedinggreennation.com/rss/index.xml',
                   title: 'BGN', topic: 'sports')
    SportsFollowsStore.add(user_id: 1, kind: 'team', value: 'eagles')
    add_final(league: league, focal: eagles, opponent_external_id: '6',
              focal_score: 24, opp_score: 20)

    get '/sports'
    # The "Eagles" short_name appears in both the score-tile and the
    # TOC button row, so we'd expect exactly 2 occurrences of the
    # /sports/team/eagles href — not 4 (which would mean duplicated
    # entries).
    href_count = last_response.body.scan(%r{href="/sports/team/eagles"}).length
    expect(href_count).to eq(2)
  end
end
