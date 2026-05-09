require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/sports_players_store'
require_relative '../app/sports_follows_store'

# Phase S7 follow-up — tennis player follows.
#
# Three surfaces:
#   1. POST /sports/players/follow + /unfollow (idempotent)
#   2. ★/☆ button on each rankings row (toggles correctly)
#   3. "My followed players" callout on /sports/tennis +
#      follow toggle on /sports/player/:slug

def make_tennis_player(slug:, full_name: 'Test Player', tour: 'atp', current_rank: 1, **extra)
  SportsPlayersStore.upsert(
    sport: 'tennis', slug: slug, full_name: full_name,
    tour: tour, current_rank: current_rank,
    source_provider: 'espn', external_id: extra[:external_id] || slug.tr('-', ''),
    country:      extra[:country],
    headshot_url: extra[:headshot_url]
  )
end

RSpec.describe 'POST /sports/players/follow' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'inserts a sports_follows row with kind=player' do
    make_tennis_player(slug: 'jannik-sinner', full_name: 'Jannik Sinner')
    post '/sports/players/follow', { slug: 'jannik-sinner' }
    expect(last_response.status).to eq(302)
    expect(SportsFollowsStore.follow?('player', 'jannik-sinner')).to be(true)
  end

  it 'is idempotent — re-follow does not 500' do
    make_tennis_player(slug: 'jannik-sinner', full_name: 'Jannik Sinner')
    post '/sports/players/follow', { slug: 'jannik-sinner' }
    post '/sports/players/follow', { slug: 'jannik-sinner' }
    expect(last_response.status).to eq(302)
    expect(SportsFollowsStore.count).to eq(1)
  end

  it '404s on an unknown player slug' do
    post '/sports/players/follow', { slug: 'nobody' }
    expect(last_response.status).to eq(404)
  end

  it '400s on missing slug' do
    post '/sports/players/follow', {}
    expect(last_response.status).to eq(400)
  end

  it 'honours return_to' do
    make_tennis_player(slug: 'jannik-sinner', full_name: 'Jannik Sinner')
    post '/sports/players/follow', { slug: 'jannik-sinner', return_to: '/sports/tennis' }
    expect(last_response.location).to end_with('/sports/tennis')
  end
end

RSpec.describe 'POST /sports/players/unfollow' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'removes the sports_follows row' do
    make_tennis_player(slug: 'jannik-sinner', full_name: 'Jannik Sinner')
    SportsFollowsStore.add(kind: 'player', value: 'jannik-sinner')
    post '/sports/players/unfollow', { slug: 'jannik-sinner' }
    expect(SportsFollowsStore.follow?('player', 'jannik-sinner')).to be(false)
  end

  it 'is idempotent — unfollow when not followed is a no-op' do
    post '/sports/players/unfollow', { slug: 'never-followed' }
    expect(last_response.status).to eq(302)
  end
end

RSpec.describe '/sports/tennis follow buttons + followed callout' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'renders ☆ on every row when no players followed' do
    make_tennis_player(slug: 'jannik-sinner', full_name: 'Jannik Sinner', tour: 'atp', current_rank: 1)
    get '/sports/tennis'
    expect(last_response.body).to include('☆')
    expect(last_response.body).not_to match(%r{<section [^>]*sports-tennis-followed})
  end

  it 'flips the followed row to ★ + renders the My followed players callout' do
    make_tennis_player(slug: 'jannik-sinner', full_name: 'Jannik Sinner', tour: 'atp', current_rank: 1)
    SportsFollowsStore.add(kind: 'player', value: 'jannik-sinner')
    get '/sports/tennis'
    expect(last_response.body).to include('My followed players')
    # The followed row's button reads ★ (and its action is /unfollow).
    rows = last_response.body.scan(%r{<tr[^>]*>[\s\S]*?</tr>})
    sinner_row = rows.find { |r| r.include?('Jannik Sinner') }
    expect(sinner_row).to include('★')
    expect(sinner_row).to include('action="/sports/players/unfollow"')
  end

  it 'sorts followed callout by current_rank ascending' do
    make_tennis_player(slug: 'sinner',  full_name: 'Sinner',  current_rank: 1)
    make_tennis_player(slug: 'alcaraz', full_name: 'Alcaraz', current_rank: 2)
    SportsFollowsStore.add(kind: 'player', value: 'alcaraz')
    SportsFollowsStore.add(kind: 'player', value: 'sinner')
    get '/sports/tennis'
    callout = last_response.body[/<section class="benchmark-section sports-tennis-followed"[\s\S]*?<\/section>/]
    expect(callout).not_to be_nil
    sinner_pos  = callout.index('Sinner')
    alcaraz_pos = callout.index('Alcaraz')
    expect(sinner_pos).to be < alcaraz_pos # rank 1 before rank 2
  end
end

RSpec.describe '/sports/player/:slug follow toggle' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'shows ☆ + Follow button when not followed' do
    make_tennis_player(slug: 'jannik-sinner', full_name: 'Jannik Sinner')
    get '/sports/player/jannik-sinner'
    expect(last_response.body).to include('☆ Not followed')
    expect(last_response.body).to include('action="/sports/players/follow"')
  end

  it 'shows ★ + Unfollow button when followed' do
    make_tennis_player(slug: 'jannik-sinner', full_name: 'Jannik Sinner')
    SportsFollowsStore.add(kind: 'player', value: 'jannik-sinner')
    get '/sports/player/jannik-sinner'
    expect(last_response.body).to include('★ Followed')
    expect(last_response.body).to include('action="/sports/players/unfollow"')
  end
end
