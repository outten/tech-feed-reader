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
