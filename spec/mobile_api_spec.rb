require_relative 'spec_helper'
require 'webauthn/fake_client'
require_relative '../app/main'
require_relative '../app/users_store'
require_relative '../app/api_tokens_store'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/read_state_store'
require_relative '../app/webauthn_credentials_store'

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
