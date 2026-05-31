require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/sports_catalog'
require_relative '../app/sports_leagues_store'
require_relative '../app/sports_follows_store'

# STUFF #70 — tournament subscriptions. Leverages the existing
# sports_leagues table + sports_follows.kind='league'. Catalog
# entries with format: :tournament get a + Follow button on
# /sports/manage/:sport and surface on /sports.

RSpec.describe SportsCatalog, 'tournament helpers (STUFF #70)' do
  it 'declares the major soccer tournaments under the soccer sport' do
    slugs = SportsCatalog.tournaments_for('soccer').map { |t| t[:slug] }
    expect(slugs).to include('fifa-world', 'fifa-womens-world', 'uefa-euro', 'copa-america', 'uefa-champions-league')
  end

  it 'declares all four tennis Grand Slams + the year-end Finals under the tennis sport' do
    slugs = SportsCatalog.tournaments_for('tennis').map { |t| t[:slug] }
    expect(slugs).to include(
      'australian-open', 'roland-garros', 'wimbledon', 'us-open-tennis',
      'atp-finals', 'wta-finals'
    )
  end

  it 'declares the headline Masters 1000 / WTA 1000 tier under tennis' do
    slugs = SportsCatalog.tournaments_for('tennis').map { |t| t[:slug] }
    expect(slugs).to include('indian-wells', 'miami-open', 'madrid-open', 'italian-open',
                              'shanghai-masters', 'paris-masters', 'wta-dubai', 'wta-beijing')
  end

  it 'declares major tournaments for cricket, golf, motorsport, and horse-racing' do
    expect(SportsCatalog.tournaments_for('cricket').map { |t| t[:slug] })
      .to include('icc-cricket-world-cup', 'icc-t20-world-cup', 'the-ashes')
    expect(SportsCatalog.tournaments_for('golf').map { |t| t[:slug] })
      .to include('the-masters', 'us-open-golf', 'the-open', 'ryder-cup', 'solheim-cup')
    expect(SportsCatalog.tournaments_for('motorsport').map { |t| t[:slug] })
      .to include('le-mans-24', 'indy-500', 'daytona-500', 'monaco-gp')
    expect(SportsCatalog.tournaments_for('horse-racing').map { |t| t[:slug] })
      .to include('us-triple-crown', 'melbourne-cup', 'prix-arc-de-triomphe')
  end

  it "seasons_for omits tournament-format entries" do
    seasons = SportsCatalog.seasons_for('soccer').map { |lg| lg[:slug] }
    expect(seasons).to include('mls', 'epl')                    # ongoing leagues kept
    expect(seasons).not_to include('fifa-world', 'uefa-euro')   # tournaments excluded
  end

  it 'find_tournament does a cross-sport slug lookup' do
    expect(SportsCatalog.find_tournament('roland-garros')[:sport]).to eq('tennis')
    expect(SportsCatalog.find_tournament('fifa-world')[:sport]).to eq('soccer')
    expect(SportsCatalog.find_tournament('mls')).to be_nil       # MLS is a season, not a tournament
    expect(SportsCatalog.find_tournament('does-not-exist')).to be_nil
  end
end

RSpec.describe 'POST /sports/leagues/follow (STUFF #70)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'creates a sports_follows entry with kind=league and lazy-upserts the league row' do
    expect(SportsLeaguesStore.find_by_slug('roland-garros')).to be_nil  # canary

    post '/sports/leagues/follow', slug: 'roland-garros'

    league = SportsLeaguesStore.find_by_slug('roland-garros')
    expect(league).not_to be_nil
    expect(league['name']).to eq('Roland Garros')
    follows = SportsFollowsStore.for_kind(1, 'league').map { |f| f['value'] }
    expect(follows).to include('roland-garros')
  end

  it 'is idempotent — following twice does not duplicate the league row or the follow' do
    post '/sports/leagues/follow', slug: 'wimbledon'
    post '/sports/leagues/follow', slug: 'wimbledon'
    expect(SportsFollowsStore.for_kind(1, 'league').count { |f| f['value'] == 'wimbledon' }).to eq(1)
  end

  it 'reuses an existing sports_leagues row when the catalog slug matches one already in the DB' do
    # FIFA World Cup is in scripts/seed_sports_data.rb's seed set,
    # so the existing path stores it as `slug='fifa-world',
    # source_provider='espn', external_id='soccer/fifa.world'`.
    existing = SportsLeaguesStore.upsert(
      slug: 'fifa-world', name: 'FIFA World Cup', sport: 'soccer',
      source_provider: 'espn', external_id: 'soccer/fifa.world'
    )
    post '/sports/leagues/follow', slug: 'fifa-world'
    # Upsert by (source_provider, external_id) finds the existing row.
    expect(SportsLeaguesStore.find_by_slug('fifa-world')['id']).to eq(existing['id'])
  end

  it '404s on an unknown catalog slug' do
    post '/sports/leagues/follow', slug: 'not-a-real-tournament'
    expect(last_response.status).to eq(404)
  end

  it '400s on missing slug param' do
    post '/sports/leagues/follow', slug: ''
    expect(last_response.status).to eq(400)
  end
end

RSpec.describe 'POST /sports/leagues/unfollow (STUFF #70)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'removes the league from sports_follows' do
    post '/sports/leagues/follow',   slug: 'australian-open'
    expect(SportsFollowsStore.for_kind(1, 'league').map { |f| f['value'] }).to include('australian-open')

    post '/sports/leagues/unfollow', slug: 'australian-open'
    expect(SportsFollowsStore.for_kind(1, 'league').map { |f| f['value'] }).not_to include('australian-open')
  end
end

RSpec.describe 'GET /sports/manage/:sport — tournaments section (STUFF #70)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'renders the Leagues + Tournaments sections separately for tennis' do
    get '/sports/manage/tennis'
    expect(last_response.status).to eq(200)
    body = last_response.body
    expect(body).to include('Leagues')
    expect(body).to include('Tournaments')
    expect(body).to include('Roland Garros')
    expect(body).to include('Wimbledon')
    expect(body).to include('action="/sports/leagues/follow"')
  end

  it 'flips the button label when the tournament is already followed' do
    SportsFollowsStore.add(user_id: 1, kind: 'league', value: 'wimbledon')
    get '/sports/manage/tennis'
    expect(last_response.body).to include('action="/sports/leagues/unfollow"')
    expect(last_response.body).to include('✓ Following')
  end
end

RSpec.describe 'GET /sports — followed tournaments section (STUFF #70)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'omits the section when the user follows no tournaments' do
    get '/sports'
    expect(last_response.body).not_to include('Following tournaments')
  end

  it 'renders a tile per followed tournament with a link to /sports/league/:slug' do
    post '/sports/leagues/follow', slug: 'wimbledon'
    get '/sports'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Following tournaments')
    expect(last_response.body).to include('Wimbledon')
    expect(last_response.body).to include('href="/sports/league/wimbledon"')
  end
end
