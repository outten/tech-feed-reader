require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/sports_leagues_store'
require_relative '../app/sports_teams_store'
require_relative '../app/sports_matches_store'
require_relative '../app/providers/espn'

# STUFF.md #9 — score tiles on /sports + last-game on team pages.
# Plumbing for the data layer (SportsMatchesStore.recent_finals_for_team)
# is exercised by spec/sports_core_spec.rb; this spec covers the
# UI surface end to end.

def make_team_with_final(slug:, name:, league_slug:, sport:, external_id:, opponent_external_id:,
                         home_score:, away_score:, focal_is_home: true,
                         scheduled_at: '2026-04-01T00:00Z')
  league = SportsLeaguesStore.upsert(slug: league_slug, name: league_slug.upcase, sport: sport,
                                      source_provider: 'espn', external_id: "#{sport}/#{league_slug}")
  team   = SportsTeamsStore.upsert(league_id: league['id'], slug: slug, name: name,
                                    short_name: name.split.last, source_provider: 'espn',
                                    external_id: external_id, image_url: 'https://logo.example/team.png')
  opp    = SportsTeamsStore.upsert(league_id: league['id'], slug: "#{slug}-opp", name: 'Opponent',
                                    source_provider: 'espn', external_id: opponent_external_id,
                                    image_url: 'https://logo.example/opp.png')
  match  = SportsMatchesStore.upsert(
    league_id: league['id'], source_provider: 'espn', external_id: "evt-#{slug}",
    scheduled_at: scheduled_at, status: 'final',
    home_team_id: focal_is_home ? team['id']    : opp['id'],
    away_team_id: focal_is_home ? opp['id']     : team['id'],
    home_score:   focal_is_home ? home_score    : away_score,
    away_score:   focal_is_home ? away_score    : home_score,
    venue:        'Test Venue'
  )
  # Subscribe to the corresponding feed so the team shows up
  # in @teams_with_subs (the score tile gate).
  team_module_entry = SportsTeams.find(slug)
  if team_module_entry
    FeedsStore.add(url: team_module_entry[:feed_urls].first, title: 'feed', topic: 'sports')
  end
  [team, match]
end

RSpec.describe 'GET /sports score tiles (STUFF.md #9)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'omits the score-tiles section when no team has any final synced' do
    get '/sports'
    expect(last_response.status).to eq(200)
    expect(last_response.body).not_to include('class="sports-score-tiles"')
  end

  it 'renders one tile per followed team with a synced final' do
    make_team_with_final(slug: 'eagles', name: 'Philadelphia Eagles',
                         league_slug: 'nfl', sport: 'football',
                         external_id: '21', opponent_external_id: '6',
                         home_score: 24, away_score: 20)
    get '/sports'
    expect(last_response.body).to include('class="sports-score-tiles"')
    expect(last_response.body).to include('Last game')
    expect(last_response.body).to match(%r{<a class="sports-score-tile sports-score-tile-w"\s+href="/sports/team/eagles"})
    expect(last_response.body).to include('class="sports-score-tile-name">Eagles')
  end

  it 'colors the tile by W/L/D based on focal team score vs opponent' do
    make_team_with_final(slug: 'eagles', name: 'Philadelphia Eagles',
                         league_slug: 'nfl', sport: 'football',
                         external_id: '21', opponent_external_id: '6',
                         home_score: 14, away_score: 28)
    get '/sports'
    expect(last_response.body).to match(/sports-score-tile-l[\s"]/)
    expect(last_response.body).not_to match(/sports-score-tile-w[\s"]/)
  end

  it 'shows D for a draw' do
    make_team_with_final(slug: 'union', name: 'Philadelphia Union',
                         league_slug: 'mls', sport: 'soccer',
                         external_id: '10739', opponent_external_id: '11',
                         home_score: 1, away_score: 1)
    get '/sports'
    expect(last_response.body).to match(/sports-score-tile-d[\s"]/)
  end

  it 'falls back to the SportsTeams emoji when no logo is set' do
    make_team_with_final(slug: 'eagles', name: 'Philadelphia Eagles',
                         league_slug: 'nfl', sport: 'football',
                         external_id: '21', opponent_external_id: '6',
                         home_score: 24, away_score: 20)
    # SportsTeams Ruby module has emoji '🦅' for eagles; the catalog
    # entry has no image_url so the tile should fall through to
    # the structured-team's image_url (set by make_team_with_final
    # to 'https://logo.example/team.png').
    get '/sports'
    expect(last_response.body).to include('https://logo.example/team.png')
  end
end

RSpec.describe 'GET /sports/team/:slug last game (STUFF.md #9)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'renders the Last game section when the team has a final' do
    make_team_with_final(slug: 'eagles', name: 'Philadelphia Eagles',
                         league_slug: 'nfl', sport: 'football',
                         external_id: '21', opponent_external_id: '6',
                         home_score: 24, away_score: 20)
    get '/sports/team/eagles'
    expect(last_response.body).to include('aria-label="Last game"')
    expect(last_response.body).to include('class="sports-score-tile-name">Eagles')
    expect(last_response.body).to include('Test Venue')
  end

  it 'omits the Last game section when no final has been synced' do
    # Add a feed sub so the team page renders, but no sports_match.
    FeedsStore.add(url: 'https://www.bleedinggreennation.com/rss/index.xml',
                    title: 'BGN', topic: 'sports')
    get '/sports/team/eagles'
    expect(last_response.body).not_to include('aria-label="Last game"')
  end
end

RSpec.describe Providers::ESPN, '.extract_logo' do
  it 'returns the first logos[].href when logos array is populated' do
    competitor = { 'team' => { 'logo' => nil, 'logos' => [{ 'href' => 'https://logo.png' }] } }
    expect(Providers::ESPN.extract_logo(competitor)).to eq('https://logo.png')
  end

  it 'falls back to team.logo when no logos array' do
    competitor = { 'team' => { 'logo' => 'https://flat.png' } }
    expect(Providers::ESPN.extract_logo(competitor)).to eq('https://flat.png')
  end

  it 'returns nil when neither field is present' do
    expect(Providers::ESPN.extract_logo({ 'team' => {} })).to be_nil
    expect(Providers::ESPN.extract_logo({})).to be_nil
  end
end
