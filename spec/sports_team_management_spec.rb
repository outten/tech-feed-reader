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

  # STUFF #52 — /sports/manage restructured to sport-first browsing.
  # Three layered routes: landing → sport → league.
  describe 'GET /sports/manage (sport-first landing)' do
    it 'lists every sport in the catalog as a card chip' do
      get '/sports/manage'
      expect(last_response.status).to eq(200)
      # Every sport in SportsCatalog::SPORTS gets a card by name.
      SportsCatalog::SPORTS.each_value do |sport|
        expect(last_response.body).to include(sport[:name]),
          "missing sport card for #{sport[:name].inspect}"
      end
    end

    it 'shows the follow count when the user has followed at least one team' do
      SportsFollowsStore.add(user_id: 1, kind: 'team', value: 'eagles')
      get '/sports/manage'
      expect(last_response.body).to match(/Currently following.*<strong>1<\/strong>/m)
    end
  end

  describe 'GET /sports/manage/:sport (leagues within a sport)' do
    it 'renders the leagues for the requested sport with chips' do
      get '/sports/manage/basketball'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('NBA')
      expect(last_response.body).to include('WNBA')
      # Women's chip surfaces the women's league at this depth.
      expect(last_response.body).to match(/sports-catalog-chip[^"]*women/)
    end

    it '404s for an unknown sport' do
      get '/sports/manage/martian-quidditch'
      expect(last_response.status).to eq(404)
    end
  end

  describe 'GET /sports/manage/:sport/:league (team grid)' do
    it 'lists every team in the league with a follow toggle' do
      get '/sports/manage/football/nfl'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('Eagles')
      expect(last_response.body).to include('+ Follow')
    end

    it 'renders the active follow state for currently-followed teams' do
      SportsFollowsStore.add(user_id: 1, kind: 'team', value: 'eagles')
      get '/sports/manage/football/nfl'
      expect(last_response.body).to include('✓ Following')
      expect(last_response.body).to match(/sports-manage-team[^"]*is-followed/)
    end

    it '404s for an unknown league' do
      get '/sports/manage/football/not-a-league'
      expect(last_response.status).to eq(404)
    end

    it 'renders an empty-state for tournament-style leagues with no persistent roster' do
      # fifa-world is now seeded with national teams; fifa-womens-world is
      # still rosterless (teams: []), so it exercises the empty state.
      get '/sports/manage/soccer/fifa-womens-world'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('No teams listed')
    end

    it 'lists the seeded national teams for the FIFA World Cup (followable)' do
      get '/sports/manage/soccer/fifa-world'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('United States')
      expect(last_response.body).to include('Brazil')
    end

    # STUFF #52 PR3 — News + podcasts panel under the team grid.
    it "renders the curated feeds panel with a Subscribe button per feed" do
      get '/sports/manage/football/nfl'
      expect(last_response.body).to include('News + podcasts')
      expect(last_response.body).to include('Bleeding Green Nation')
      expect(last_response.body).to include('+ Subscribe')
    end

    it "flips Subscribe → ✓ Subscribed when the user already has that feed" do
      FeedsStore.add_for_user(user_id: 1,
                              url: 'https://www.bleedinggreennation.com/rss/index.xml',
                              title: 'Bleeding Green Nation',
                              fetch_interval_seconds: FeedsStore::PUBLISHER_INTERVAL,
                              topic: 'sports')
      get '/sports/manage/football/nfl'
      expect(last_response.body).to include('✓ Subscribed')
    end

    # STUFF #52 PR3 — notable-players line on each team card.
    it "lists notable players under the team name when the catalog has them" do
      get '/sports/manage/football/nfl'
      expect(last_response.body).to include('Jalen Hurts')
      expect(last_response.body).to match(/sports-manage-team-players/)
    end
  end

  describe 'POST /sports/feeds/subscribe' do
    it 'subscribes the user to the URL when it\'s in the FeedCatalog' do
      url = 'https://www.bleedinggreennation.com/rss/index.xml'
      expect(FeedsStore.for_user(1).map { |f| f['url'] }).not_to include(url)
      post '/sports/feeds/subscribe', url: url, return_to: '/sports/manage/football/nfl'
      expect(last_response).to be_redirect
      expect(FeedsStore.for_user(1).map { |f| f['url'] }).to include(url)
    end

    it 'is idempotent on a re-subscribe (still redirects)' do
      url = 'https://www.bleedinggreennation.com/rss/index.xml'
      FeedsStore.add_for_user(user_id: 1, url: url, title: 'Bleeding Green Nation',
                              fetch_interval_seconds: FeedsStore::PUBLISHER_INTERVAL, topic: 'sports')
      post '/sports/feeds/subscribe', url: url
      expect(last_response).to be_redirect
    end

    it '422s when the URL isn\'t in the FeedCatalog (no arbitrary subscribes)' do
      post '/sports/feeds/subscribe', url: 'https://malicious.example.com/rss'
      expect(last_response.status).to eq(422)
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

    # STUFF #52 — when a team exists in SportsCatalog but hasn't been
    # seeded into the DB yet, follow upserts league + team on demand.
    it 'upserts a catalog-only team + its league into the DB on follow' do
      # 'tennis-sinner' lives in SportsCatalog but is not pre-seeded here.
      expect(SportsTeamsStore.find_by_slug('tennis-sinner')).to be_nil
      post '/sports/teams/follow', slug: 'tennis-sinner'
      expect(last_response).to be_redirect
      team = SportsTeamsStore.find_by_slug('tennis-sinner')
      expect(team).not_to be_nil
      expect(team['name']).to eq('Jannik Sinner')
      league = SportsLeaguesStore.find(team['league_id'])
      expect(league['slug']).to eq('atp')
      expect(SportsFollowsStore.follow?(1, 'team', 'tennis-sinner')).to be(true)
    end

    it 'skips the ESPN worker enqueue for catalog-only teams (no source_provider=espn)' do
      # 'real-madrid-bc' is in the catalog (EuroLeague) without an ESPN
      # external_id — we don't want a perform_async with a bogus team id.
      expect(SportsTeamFetchWorker).not_to receive(:perform_async)
      post '/sports/teams/follow', slug: 'real-madrid-bc'
      expect(last_response).to be_redirect
      expect(SportsFollowsStore.follow?(1, 'team', 'real-madrid-bc')).to be(true)
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
