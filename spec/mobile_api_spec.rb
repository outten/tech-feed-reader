require_relative 'spec_helper'
require 'webauthn/fake_client'
require_relative '../app/main'
require_relative '../app/users_store'
require_relative '../app/api_tokens_store'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/read_state_store'
require_relative '../app/webauthn_credentials_store'
require_relative '../app/feed_catalog'
require_relative '../app/mute_rules_store'
require_relative '../app/sports_catalog'
require_relative '../app/sports_leagues_store'
require_relative '../app/sports_teams_store'
require_relative '../app/sports_matches_store'
require_relative '../app/sports_standings_store'
require_relative '../app/sports_players_store'
require_relative '../app/sports_follows_store'
require_relative '../app/stock_follows_store'
require_relative '../app/stock_quotes_store'
require_relative '../app/stock_quote_provider'
require_relative '../app/stock_news_feed'
require_relative '../app/radio_catalog'
require_relative '../app/radio_store'

# ios-app change — mobile JSON API (openspec/changes/ios-app/specs/mobile-api).
# Covers native-client token issuance from the existing WebAuthn ceremonies
# and the token-authenticated /api/v1/* endpoints.

RSpec.describe 'Mobile API' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  let(:fake_client) { WebAuthn::FakeClient.new(ENV['WEBAUTHN_ORIGIN']) }

  def sign_up_native(username: 'mobileuser')
    post '/api/auth/register/options', { username: username }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }
    options = JSON.parse(last_response.body)['publicKey']
    attestation = fake_client.create(challenge: options['challenge'])
    post '/api/auth/register/verify', attestation.merge('native' => true).to_json,
         { 'CONTENT_TYPE' => 'application/json' }
    JSON.parse(last_response.body)
  end

  def auth_header(token)
    { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
  end

  describe 'native token issuance' do
    it 'register/verify returns an api_token when native: true' do
      result = sign_up_native
      expect(result['ok']).to be true
      expect(result['api_token']).to be_a(String)
      expect(result['api_token']).not_to be_empty
    end

    it 'register/verify omits api_token for browser (non-native) requests' do
      post '/api/auth/register/options', { username: 'webuser' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }
      options = JSON.parse(last_response.body)['publicKey']
      attestation = fake_client.create(challenge: options['challenge'])
      post '/api/auth/register/verify', attestation.to_json,
           { 'CONTENT_TYPE' => 'application/json' }
      result = JSON.parse(last_response.body)
      expect(result['ok']).to be true
      expect(result).not_to have_key('api_token')
    end

    it 'login/verify returns an api_token when native: true' do
      sign_up_native(username: 'loginuser')
      user = UsersStore.find_by_username('loginuser')
      creds = WebauthnCredentialsStore.for_user(user['id'])

      post '/api/auth/login/options', { username: 'loginuser' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }
      options = JSON.parse(last_response.body)['publicKey']
      assertion = fake_client.get(challenge: options['challenge'])
      post '/api/auth/login/verify', assertion.merge('native' => true).to_json,
           { 'CONTENT_TYPE' => 'application/json' }
      result = JSON.parse(last_response.body)
      expect(result['ok']).to be true
      expect(result['api_token']).to be_a(String)
      expect(creds).not_to be_empty
    end
  end

  describe 'GET /api/v1/feeds' do
    it '401s without a bearer token' do
      get '/api/v1/feeds'
      expect(last_response.status).to eq(401)
    end

    it '401s with an invalid bearer token' do
      get '/api/v1/feeds', {}, auth_header('not-a-real-token')
      expect(last_response.status).to eq(401)
    end

    it 'lists the token owner\'s subscribed feeds' do
      result = sign_up_native
      user   = UsersStore.find_by_username('mobileuser')
      FeedsStore.add_for_user(user_id: user['id'], url: 'https://example.com/feed.xml', title: 'Example Feed')

      get '/api/v1/feeds', {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      feeds = JSON.parse(last_response.body)
      expect(feeds.length).to eq(1)
      expect(feeds.first['title']).to eq('Example Feed')
    end
  end

  describe 'articles + read-state + subscriptions' do
    let(:result) { sign_up_native }
    let(:user)   { UsersStore.find_by_username(result['username']) }
    let!(:feed)  { FeedsStore.add_for_user(user_id: user['id'], url: 'https://example.com/feed.xml', title: 'Example Feed').first }
    let!(:article) do
      ArticlesStore.import(feed_id: feed['id'], entries: [{
        uid: 'art-1', title: 'Hello World', url: 'https://example.com/1',
        author: nil, published_at: Time.now.utc.iso8601,
        content_html: '<p>Hi</p>', content_text: 'Hi'
      }])
      ArticlesStore.find_by_uid('art-1')
    end

    it 'GET /api/v1/articles returns articles for the subscribed feed' do
      get '/api/v1/articles', { feed_id: feed['id'] }, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      articles = JSON.parse(last_response.body)
      expect(articles.map { |a| a['uid'] }).to include('art-1')
    end

    it 'GET /api/v1/articles/:uid returns a single article with read state' do
      get "/api/v1/articles/#{article['uid']}", {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body['title']).to eq('Hello World')
      expect(body['read'].to_i).to eq(0)
    end

    it 'GET /api/v1/articles/:uid 404s for an unknown uid' do
      get '/api/v1/articles/does-not-exist', {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(404)
    end

    it 'POST /api/v1/read_state marks an article read' do
      post '/api/v1/read_state', { uid: article['uid'], read: true }.to_json,
           auth_header(result['api_token']).merge('CONTENT_TYPE' => 'application/json')
      expect(last_response.status).to eq(200)
      state = ReadStateStore.get(user['id'], article['id'])
      expect(state['read'].to_i).to eq(1)
    end

    it 'POST /api/v1/subscriptions subscribes to a new feed' do
      post '/api/v1/subscriptions', { url: 'https://example.com/other.xml' }.to_json,
           auth_header(result['api_token']).merge('CONTENT_TYPE' => 'application/json')
      expect(last_response.status).to eq(201)
      feeds = FeedsStore.for_user(user['id'])
      expect(feeds.map { |f| f['url'] }).to include('https://example.com/other.xml')
    end

    it 'DELETE /api/v1/subscriptions/:id unsubscribes' do
      delete "/api/v1/subscriptions/#{feed['id']}", {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      expect(FeedsStore.for_user(user['id'])).to be_empty
    end

    it 'GET /api/v1/articles?state=bookmarked filters to bookmarked articles' do
      ReadStateStore.mark_bookmarked(user['id'], article['id'], value: true)
      get '/api/v1/articles', { state: 'bookmarked' }, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      articles = JSON.parse(last_response.body)
      expect(articles.map { |a| a['uid'] }).to eq(['art-1'])
    end

    it 'GET /api/v1/articles?state=unread excludes read articles' do
      ReadStateStore.mark_read(user['id'], article['id'], read: true)
      get '/api/v1/articles', { state: 'unread' }, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      articles = JSON.parse(last_response.body)
      expect(articles.map { |a| a['uid'] }).not_to include('art-1')
    end

    it 'GET /api/v1/search returns matching articles' do
      get '/api/v1/search', { q: 'Hello' }, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      articles = JSON.parse(last_response.body)
      expect(articles.map { |a| a['uid'] }).to include('art-1')
    end

    it 'GET /api/v1/search with no q returns an empty array' do
      get '/api/v1/search', {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)).to eq([])
    end

    it 'GET /api/v1/tags lists the user\'s tags' do
      TagsStore.add(user_id: user['id'], name: 'Ruby', match_kind: 'keyword', match_value: 'ruby')
      get '/api/v1/tags', {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      tags = JSON.parse(last_response.body)
      expect(tags.map { |t| t['name'] }).to eq(['Ruby'])
    end

    it 'GET /api/v1/articles?tag_id filters to tagged articles' do
      tag = TagsStore.add(user_id: user['id'], name: 'Ruby', match_kind: 'keyword', match_value: 'ruby')
      TagsStore.tag_article(article['id'], tag['id'])
      get '/api/v1/articles', { tag_id: tag['id'] }, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      articles = JSON.parse(last_response.body)
      expect(articles.map { |a| a['uid'] }).to eq(['art-1'])
    end

    it 'GET /api/v1/topics returns an array' do
      get '/api/v1/topics', {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)).to be_an(Array)
    end

    it 'GET /api/v1/topics/:term returns matching articles' do
      get '/api/v1/topics/Hello', {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      articles = JSON.parse(last_response.body)
      expect(articles.map { |a| a['uid'] }).to include('art-1')
    end
  end

  describe 'feed discovery (Phase 4a)' do
    let(:result) { sign_up_native }
    let(:user)   { UsersStore.find_by_username(result['username']) }

    it 'GET /api/v1/feed_catalog groups the catalog by category with labels' do
      get '/api/v1/feed_catalog', {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      groups = JSON.parse(last_response.body)
      aggregator = groups.find { |g| g['category'] == 'aggregator' }
      expect(aggregator['label']).to eq('Aggregators')
      expect(aggregator['feeds'].map { |f| f['url'] }).to include('https://news.ycombinator.com/rss')
    end

    it 'GET /api/v1/feed_catalog/recommended scores against current subscriptions' do
      FeedsStore.add_for_user(user_id: user['id'], url: 'https://lobste.rs/rss', title: 'Lobsters')
      get '/api/v1/feed_catalog/recommended', {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      recommended = JSON.parse(last_response.body)
      expect(recommended.map { |f| f['url'] }).not_to include('https://lobste.rs/rss')
    end

    it 'GET /api/v1/feed_catalog/recommended returns an empty array cold-start' do
      get '/api/v1/feed_catalog/recommended', {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)).to eq([])
    end

    it 'GET /api/v1/feeds/popular?type=news returns an array' do
      get '/api/v1/feeds/popular', { type: 'news' }, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)).to be_an(Array)
    end

    it 'GET /api/v1/feeds/popular rejects an invalid type' do
      get '/api/v1/feeds/popular', { type: 'bogus' }, auth_header(result['api_token'])
      expect(last_response.status).to eq(400)
    end

    it 'mute rules: add, list, remove' do
      post '/api/v1/mute_rules', { kind: 'keyword', value: 'crypto' }.to_json,
           auth_header(result['api_token']).merge('CONTENT_TYPE' => 'application/json')
      expect(last_response.status).to eq(201)

      get '/api/v1/mute_rules', {}, auth_header(result['api_token'])
      rules = JSON.parse(last_response.body)
      expect(rules.map { |r| [r['kind'], r['value']] }).to include(['keyword', 'crypto'])

      delete '/api/v1/mute_rules', { kind: 'keyword', value: 'crypto' }, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)

      get '/api/v1/mute_rules', {}, auth_header(result['api_token'])
      expect(JSON.parse(last_response.body)).to be_empty
    end
  end

  describe 'podcasts + youtube (Phase 5)' do
    let(:result) { sign_up_native }
    let(:user)   { UsersStore.find_by_username(result['username']) }

    it 'GET /api/v1/podcasts lists feeds with audio-enclosure articles' do
      podcast_feed = FeedsStore.add_for_user(user_id: user['id'], url: 'https://example.com/podcast.xml', title: 'My Podcast').first
      text_feed    = FeedsStore.add_for_user(user_id: user['id'], url: 'https://example.com/text.xml', title: 'Text Feed').first
      ArticlesStore.import(feed_id: podcast_feed['id'], entries: [{
        uid: 'ep-1', title: 'Episode 1', url: 'https://example.com/ep1',
        author: nil, published_at: Time.now.utc.iso8601,
        content_html: '', content_text: '', audio_url: 'https://example.com/ep1.mp3',
        audio_mime_type: 'audio/mpeg', audio_duration_seconds: 1800
      }])
      ArticlesStore.import(feed_id: text_feed['id'], entries: [{
        uid: 'txt-1', title: 'Article', url: 'https://example.com/txt1',
        author: nil, published_at: Time.now.utc.iso8601, content_html: '', content_text: ''
      }])

      get '/api/v1/podcasts', {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      feeds = JSON.parse(last_response.body)
      expect(feeds.map { |f| f['id'] }).to eq([podcast_feed['id']])
      expect(feeds.first['episode_count'].to_i).to eq(1)
    end

    it 'GET /api/v1/youtube/channels lists subscribed YouTube channel feeds' do
      channel = FeedsStore.add_for_user(
        user_id: user['id'], url: 'https://www.youtube.com/feeds/videos.xml?channel_id=UC123', title: 'A Channel'
      ).first
      ArticlesStore.import(feed_id: channel['id'], entries: [{
        uid: 'vid-1', title: 'Video 1', url: 'https://www.youtube.com/watch?v=abcdefghijk',
        author: nil, published_at: Time.now.utc.iso8601, content_html: '', content_text: ''
      }])

      get '/api/v1/youtube/channels', {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      channels = JSON.parse(last_response.body)
      expect(channels.map { |c| c['id'] }).to eq([channel['id']])
      expect(channels.first['video_count'].to_i).to eq(1)
      expect(channels.first['latest_uid']).to eq('vid-1')
    end
  end

  describe 'sports (Phase 6a)' do
    let(:result) { sign_up_native }
    let(:user)   { UsersStore.find_by_username(result['username']) }

    it 'GET /api/v1/sports lists catalog sports' do
      get '/api/v1/sports', {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      sports = JSON.parse(last_response.body)
      football = sports.find { |s| s['slug'] == 'football' }
      expect(football['name']).to eq('American Football')
    end

    it 'GET /api/v1/sports/:sport/leagues lists leagues without their team arrays' do
      get '/api/v1/sports/football/leagues', {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      leagues = JSON.parse(last_response.body)
      nfl = leagues.find { |lg| lg['slug'] == 'nfl' }
      expect(nfl['name']).to eq('NFL')
      expect(nfl).not_to have_key('teams')
    end

    it 'GET /api/v1/sports/:sport/leagues 404s for an unknown sport' do
      get '/api/v1/sports/quidditch/leagues', {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(404)
    end

    it 'GET /api/v1/sports/:sport/:league/teams lists catalog teams' do
      get '/api/v1/sports/football/nfl/teams', {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      teams = JSON.parse(last_response.body)
      expect(teams.map { |t| t['slug'] }).to include('eagles')
    end

    it 'follows a catalog-only team, materializing it into the database' do
      expect(SportsTeamsStore.find_by_slug('eagles')).to be_nil

      post '/api/v1/sports/teams/follow', { slug: 'eagles' }.to_json,
           auth_header(result['api_token']).merge('CONTENT_TYPE' => 'application/json')
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)).to include('followed' => true)

      team = SportsTeamsStore.find_by_slug('eagles')
      expect(team).not_to be_nil
      expect(SportsFollowsStore.follow?(user['id'], 'team', 'eagles')).to be true
    end

    it 'unfollows a team' do
      SportsFollowsStore.add(user_id: user['id'], kind: 'team', value: 'eagles')
      delete '/api/v1/sports/teams/follow', { slug: 'eagles' }, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      expect(SportsFollowsStore.follow?(user['id'], 'team', 'eagles')).to be false
    end

    it 'follows and unfollows a league' do
      post '/api/v1/sports/leagues/follow', { slug: 'nfl' }.to_json,
           auth_header(result['api_token']).merge('CONTENT_TYPE' => 'application/json')
      expect(last_response.status).to eq(200)
      expect(SportsFollowsStore.follow?(user['id'], 'league', 'nfl')).to be true

      delete '/api/v1/sports/leagues/follow', { slug: 'nfl' }, auth_header(result['api_token'])
      expect(SportsFollowsStore.follow?(user['id'], 'league', 'nfl')).to be false
    end

    it 'GET /api/v1/sports/teams/:slug returns basic info for a catalog-only team (not 404)' do
      get '/api/v1/sports/teams/eagles', {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body['team']['name']).to eq('Philadelphia Eagles')
      expect(body['standings']).to be_nil
      expect(body['followed']).to be false
    end

    it 'GET /api/v1/sports/teams/:slug returns full detail once synced' do
      league = SportsLeaguesStore.upsert(slug: 'nfl', name: 'NFL', sport: 'football', source_provider: 'espn', external_id: 'football/nfl')
      team = SportsTeamsStore.upsert(league_id: league['id'], slug: 'eagles', name: 'Philadelphia Eagles', source_provider: 'espn', external_id: '21')
      SportsStandingsStore.upsert(league_id: league['id'], team_id: team['id'], group_name: 'NFC East', source_provider: 'espn', position: 1)

      get '/api/v1/sports/teams/eagles', {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body['league']['slug']).to eq('nfl')
      expect(body['standings']['group_name']).to eq('NFC East')
    end

    it 'GET /api/v1/sports/leagues/:slug 404s for an unknown league' do
      get '/api/v1/sports/leagues/does-not-exist', {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(404)
    end

    it 'GET /api/v1/sports/leagues/:slug returns standings grouped by group_name' do
      league = SportsLeaguesStore.upsert(slug: 'nfl', name: 'NFL', sport: 'football', source_provider: 'espn', external_id: 'football/nfl')
      team = SportsTeamsStore.upsert(league_id: league['id'], slug: 'eagles', name: 'Philadelphia Eagles', source_provider: 'espn', external_id: '21')
      SportsStandingsStore.upsert(league_id: league['id'], team_id: team['id'], group_name: 'NFC East', source_provider: 'espn', position: 1)

      get '/api/v1/sports/leagues/nfl', {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body['standings'].first['group_name']).to eq('NFC East')
      expect(body['teams_by_id'][team['id'].to_s]['slug']).to eq('eagles')
    end

    it 'GET /api/v1/sports/players/:slug materializes a catalog notable-player chip' do
      team_with_players = SportsCatalog.all_teams.find { |t| (t[:players] || []).any? }
      player_name = team_with_players[:players].first
      slug = "#{team_with_players[:slug]}-#{player_name.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-+|-+$/, '')}"

      get "/api/v1/sports/players/#{slug}", {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body['player']['full_name']).to eq(player_name)
      expect(SportsPlayersStore.find_by_slug(slug)).not_to be_nil
    end

    it 'GET /api/v1/sports/overview lists followed teams and live matches' do
      league = SportsLeaguesStore.upsert(slug: 'nfl', name: 'NFL', sport: 'football', source_provider: 'espn', external_id: 'football/nfl')
      team = SportsTeamsStore.upsert(league_id: league['id'], slug: 'eagles', name: 'Philadelphia Eagles', source_provider: 'espn', external_id: '21')
      SportsFollowsStore.add(user_id: user['id'], kind: 'team', value: 'eagles')

      get '/api/v1/sports/overview', {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body['followed_teams'].map { |t| t['slug'] }).to eq(['eagles'])
    end
  end

  describe 'stocks (Phase 7)' do
    let(:result) { sign_up_native }
    let(:user)   { UsersStore.find_by_username(result['username']) }

    it 'GET /api/v1/stocks/search returns an array (provider unavailable in test env)' do
      get '/api/v1/stocks/search', { q: 'apple' }, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)).to eq([])
    end

    it 'GET /api/v1/stocks/:symbol returns a cached quote when fresh' do
      StockQuotesStore.upsert(symbol: 'AAPL', name: 'Apple Inc', price: 150.0)
      get '/api/v1/stocks/AAPL', {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body['quote']['name']).to eq('Apple Inc')
      expect(body['followed']).to be false
    end

    it 'GET /api/v1/stocks/:symbol returns quote: nil when uncached and provider unavailable' do
      get '/api/v1/stocks/ZZZZ', {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)['quote']).to be_nil
    end

    it 'follows a symbol, subscribing its news feed' do
      post '/api/v1/stocks/follow', { symbol: 'aapl', name: 'Apple Inc' }.to_json,
           auth_header(result['api_token']).merge('CONTENT_TYPE' => 'application/json')
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)).to include('symbol' => 'AAPL', 'followed' => true)
      expect(StockFollowsStore.follow?(user['id'], 'AAPL')).to be true

      feed = FeedsStore.find_by_url(StockNewsFeed.url_for('AAPL'))
      expect(feed).not_to be_nil
      expect(FeedsStore.subscribed?(user['id'], feed['id'])).to be true
    end

    it 'unfollows a symbol, unsubscribing its news feed' do
      StockFollowsStore.add(user_id: user['id'], symbol: 'AAPL')
      feed = StockNewsFeed.ensure_feed!('AAPL')
      FeedsStore.subscribe(user['id'], feed['id'])

      delete '/api/v1/stocks/follow', { symbol: 'AAPL' }, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      expect(StockFollowsStore.follow?(user['id'], 'AAPL')).to be false
      expect(FeedsStore.subscribed?(user['id'], feed['id'])).to be false
    end

    it 'GET /api/v1/stocks/ticker includes major indices even when uncached' do
      get '/api/v1/stocks/ticker', {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      ticker = JSON.parse(last_response.body)
      expect(ticker.map { |t| t['symbol'] }).to include('SPY')
    end

    it 'GET /api/v1/stocks/ticker includes followed symbols' do
      StockFollowsStore.add(user_id: user['id'], symbol: 'AAPL', name: 'Apple Inc')
      get '/api/v1/stocks/ticker', {}, auth_header(result['api_token'])
      ticker = JSON.parse(last_response.body)
      expect(ticker.map { |t| t['symbol'] }).to include('AAPL')
    end

    it 'GET /api/v1/stocks/sparklines returns an object keyed by index symbol' do
      get '/api/v1/stocks/sparklines', {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      sparklines = JSON.parse(last_response.body)
      expect(sparklines).to have_key('SPY')
    end
  end

  describe 'misc content (Phase 8a)' do
    let(:result) { sign_up_native }
    let(:user)   { UsersStore.find_by_username(result['username']) }

    it 'GET /api/v1/articles?topic filters to that topic' do
      humor_feed = FeedsStore.add_for_user(user_id: user['id'], url: 'https://example.com/comic.xml', title: 'A Comic', topic: 'humor').first
      other_feed = FeedsStore.add_for_user(user_id: user['id'], url: 'https://example.com/other.xml', title: 'Other').first
      ArticlesStore.import(feed_id: humor_feed['id'], entries: [{
        uid: 'comic-1', title: 'Panel', url: 'https://example.com/panel1',
        author: nil, published_at: Time.now.utc.iso8601, content_html: '', content_text: ''
      }])
      ArticlesStore.import(feed_id: other_feed['id'], entries: [{
        uid: 'other-1', title: 'Not a comic', url: 'https://example.com/other1',
        author: nil, published_at: Time.now.utc.iso8601, content_html: '', content_text: ''
      }])

      get '/api/v1/articles', { topic: 'humor' }, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      articles = JSON.parse(last_response.body)
      expect(articles.map { |a| a['uid'] }).to eq(['comic-1'])
    end

    it 'GET /api/v1/radio/stations lists the catalog grouped, with followed_ids' do
      get '/api/v1/radio/stations', {}, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body['groups']).not_to be_empty
      expect(body['groups'].first).to have_key('stations')
      expect(body['followed_ids']).to eq([])
    end

    it 'follows and unfollows a radio station' do
      RadioStore.seed_catalog!
      station = RadioStore.all_stations.first

      post '/api/v1/radio/follow', { station_id: station['id'] }.to_json,
           auth_header(result['api_token']).merge('CONTENT_TYPE' => 'application/json')
      expect(last_response.status).to eq(200)
      expect(RadioStore.following?(user['id'], station['id'])).to be true

      delete '/api/v1/radio/follow', { station_id: station['id'] }, auth_header(result['api_token'])
      expect(last_response.status).to eq(200)
      expect(RadioStore.following?(user['id'], station['id'])).to be false
    end

    it 'POST /api/v1/radio/follow 404s for an unknown station_id' do
      post '/api/v1/radio/follow', { station_id: 999_999 }.to_json,
           auth_header(result['api_token']).merge('CONTENT_TYPE' => 'application/json')
      expect(last_response.status).to eq(404)
    end
  end

  describe 'DELETE /api/v1/session' do
    it 'revokes the token so subsequent requests 401' do
      result = sign_up_native
      token  = result['api_token']

      delete '/api/v1/session', {}, auth_header(token)
      expect(last_response.status).to eq(200)

      get '/api/v1/feeds', {}, auth_header(token)
      expect(last_response.status).to eq(401)
    end
  end
end
