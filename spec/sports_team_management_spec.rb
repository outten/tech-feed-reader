require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/providers/espn'
require_relative '../app/sports_leagues_store'
require_relative '../app/sports_teams_store'
require_relative '../app/sports_follows_store'
require_relative '../app/workers/sports_team_fetch_worker'

# STUFF #45 — sports team management. Provider catalog method +
# follow/unfollow routes + manage page + eager-fetch worker.
RSpec.describe 'Sports team management (STUFF #45)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  def make_response(code, body)
    double('Response', code: code.to_s, body: body.is_a?(String) ? body : JSON.generate(body))
  end

  describe 'Providers::ESPN.teams_for_league' do
    let(:nfl_body) do
      {
        'sports' => [
          {
            'leagues' => [
              {
                'teams' => [
                  { 'team' => {
                      'id' => '21', 'slug' => 'philadelphia-eagles',
                      'displayName' => 'Philadelphia Eagles',
                      'shortDisplayName' => 'Eagles', 'abbreviation' => 'PHI',
                      'location' => 'Philadelphia',
                      'logos' => [{ 'href' => 'https://example.com/eagles.png' }]
                    } },
                  { 'team' => {
                      'id' => '17', 'slug' => 'new-england-patriots',
                      'displayName' => 'New England Patriots',
                      'shortDisplayName' => 'Patriots', 'abbreviation' => 'NE',
                      'location' => 'New England',
                      'logos' => [{ 'href' => 'https://example.com/pats.png' }]
                    } }
                ]
              }
            ]
          }
        ]
      }
    end

    it 'parses the full roster from ESPN /teams response' do
      seen = nil
      stub = ->(url) { seen = url; make_response(200, nfl_body) }
      teams = Providers::ESPN.teams_for_league(sport_path: 'football/nfl', http_get: stub)
      expect(seen).to eq('https://site.api.espn.com/apis/site/v2/sports/football/nfl/teams')
      expect(teams.length).to eq(2)
      expect(teams.first).to include(
        external_id: '21',
        slug:        'philadelphia-eagles',
        name:        'Philadelphia Eagles',
        short_name:  'Eagles',
        location:    'Philadelphia',
        image_url:   'https://example.com/eagles.png'
      )
    end

    it 'returns [] (logged) on a non-200 response' do
      stub = ->(_url) { make_response(500, '') }
      expect(Providers::ESPN.teams_for_league(sport_path: 'football/nfl', http_get: stub)).to eq([])
    end

    it 'returns [] on malformed JSON' do
      stub = ->(_url) { make_response(200, 'not json') }
      expect(Providers::ESPN.teams_for_league(sport_path: 'football/nfl', http_get: stub)).to eq([])
    end

    it 'tolerates teams with missing optional fields' do
      body = { 'sports' => [{ 'leagues' => [{ 'teams' => [
        { 'team' => { 'id' => '99', 'displayName' => 'Bare Team' } }
      ] }] }] }
      stub = ->(_url) { make_response(200, body) }
      teams = Providers::ESPN.teams_for_league(sport_path: 'football/nfl', http_get: stub)
      expect(teams.first[:external_id]).to eq('99')
      expect(teams.first[:image_url]).to be_nil
    end
  end

  describe 'GET /sports/manage' do
    before do
      @nfl = SportsLeaguesStore.upsert(slug: 'nfl', name: 'NFL', sport: 'football',
                                       source_provider: 'espn', external_id: 'football/nfl', country: 'US')
      @eagles = SportsTeamsStore.upsert(league_id: @nfl['id'], slug: 'eagles',
                                        name: 'Philadelphia Eagles', short_name: 'Eagles',
                                        source_provider: 'espn', external_id: '21')
      @pats = SportsTeamsStore.upsert(league_id: @nfl['id'], slug: 'patriots',
                                      name: 'New England Patriots', short_name: 'Patriots',
                                      source_provider: 'espn', external_id: '17')
    end

    it 'lists every team in the league with a follow toggle' do
      get '/sports/manage'
      expect(last_response.status).to eq(200)
      # Cards show short_name in compact layout, full name on hover/title.
      expect(last_response.body).to include('Eagles', 'Patriots')
      expect(last_response.body).to include('+ Follow')
    end

    it 'renders the active follow state for currently-followed teams' do
      SportsFollowsStore.add(user_id: 1, kind: 'team', value: 'eagles')
      get '/sports/manage'
      expect(last_response.body).to include('✓ Following')
      # Match on the followed-card decoration class so a refactor that
      # silently drops the green-edge accent fails this spec.
      expect(last_response.body).to match(/sports-manage-team[^"]*is-followed/)
    end
  end

  describe 'POST /sports/teams/follow' do
    before do
      league = SportsLeaguesStore.upsert(slug: 'nba', name: 'NBA', sport: 'basketball',
                                         source_provider: 'espn', external_id: 'basketball/nba')
      @sixers = SportsTeamsStore.upsert(league_id: league['id'], slug: 'sixers',
                                        name: 'Philadelphia 76ers', short_name: 'Sixers',
                                        source_provider: 'espn', external_id: '20')
    end

    it 'adds the follow + enqueues a SportsTeamFetchWorker for the team' do
      expect(SportsTeamFetchWorker).to receive(:perform_async).with(@sixers['id'])
      post '/sports/teams/follow', slug: 'sixers'
      expect(SportsFollowsStore.follow?(1, 'team', 'sixers')).to be(true)
      expect(last_response).to be_redirect
    end

    it '404s when the slug doesn\'t exist' do
      post '/sports/teams/follow', slug: 'martians'
      expect(last_response.status).to eq(404)
    end

    it 'is idempotent on re-follow (no duplicate row, still enqueues worker)' do
      SportsFollowsStore.add(user_id: 1, kind: 'team', value: 'sixers')
      expect(SportsTeamFetchWorker).to receive(:perform_async).with(@sixers['id'])
      expect {
        post '/sports/teams/follow', slug: 'sixers'
      }.not_to(change { SportsFollowsStore.for_kind(1, 'team').length })
    end
  end

  describe 'POST /sports/teams/unfollow' do
    before do
      league = SportsLeaguesStore.upsert(slug: 'nba', name: 'NBA', sport: 'basketball',
                                         source_provider: 'espn', external_id: 'basketball/nba')
      SportsTeamsStore.upsert(league_id: league['id'], slug: 'sixers',
                              name: 'Philadelphia 76ers',
                              source_provider: 'espn', external_id: '20')
      SportsFollowsStore.add(user_id: 1, kind: 'team', value: 'sixers')
    end

    it 'removes the follow' do
      post '/sports/teams/unfollow', slug: 'sixers'
      expect(SportsFollowsStore.follow?(1, 'team', 'sixers')).to be(false)
    end
  end

  describe 'Manage ▾ dropdown includes Sports' do
    it 'renders a /sports/manage entry in the Manage dropdown' do
      get '/articles'
      expect(last_response.body).to match(%r{<a href="/sports/manage"[^>]*role="menuitem">Sports</a>})
    end
  end
end
