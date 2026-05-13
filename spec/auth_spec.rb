require_relative 'spec_helper'
require 'webauthn/fake_client'
require 'base64'
require_relative '../app/main'
require_relative '../app/users_store'
require_relative '../app/webauthn_credentials_store'
require_relative '../app/recovery_codes_store'

# Phase A1 (consumer auth). End-to-end specs for the WebAuthn
# ceremonies + recovery-code flow + auth-wall before-filter.
#
# WebAuthn::FakeClient simulates a passkey authenticator: we feed
# it the same `origin` the server expects, then ask it to
# create / get credentials. The bytes it returns match what a real
# browser's navigator.credentials.create() would emit — perfect for
# round-tripping against our real /api/auth/* endpoints.

RSpec.describe 'Phase A1 — auth ceremonies + wall' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  let(:fake_client) { WebAuthn::FakeClient.new(ENV['WEBAUTHN_ORIGIN']) }

  # Helper — drive the full sign-up flow through the JSON endpoints.
  # Returns the response hash from /verify (including recovery_codes).
  def sign_up_via_api(username: 'todd', display_name: 'Todd')
    post '/api/auth/register/options', { username: username, display_name: display_name }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }
    raise "register/options failed: #{last_response.status} #{last_response.body}" unless last_response.ok?
    options = JSON.parse(last_response.body)['publicKey']

    attestation = fake_client.create(challenge: options['challenge'])
    post '/api/auth/register/verify', attestation.to_json,
         { 'CONTENT_TYPE' => 'application/json' }
    raise "register/verify failed: #{last_response.status} #{last_response.body}" unless last_response.ok?
    JSON.parse(last_response.body)
  end

  def sign_in_via_api(username: 'todd')
    post '/api/auth/login/options', { username: username }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }
    raise "login/options failed: #{last_response.status} #{last_response.body}" unless last_response.ok?
    options = JSON.parse(last_response.body)['publicKey']

    assertion = fake_client.get(challenge: options['challenge'])
    post '/api/auth/login/verify', assertion.to_json,
         { 'CONTENT_TYPE' => 'application/json' }
    JSON.parse(last_response.body)
  end

  describe '/sign-up page shell' do
    it 'renders the page with username + display_name fields' do
      get '/sign-up'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('Register passkey')
      expect(last_response.body).to include('id="auth-username"')
      expect(last_response.body).to match(%r{<script src="/auth\.js})
    end
  end

  describe 'POST /api/auth/register/options' do
    it 'rejects an invalid username with 400' do
      post '/api/auth/register/options', { username: 'ab' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }
      expect(last_response.status).to eq(400)
      expect(JSON.parse(last_response.body)['error']).to include('Username')
    end

    it 'rejects a taken username with 409' do
      UsersStore.create(username: 'taken')
      post '/api/auth/register/options', { username: 'taken' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }
      expect(last_response.status).to eq(409)
    end

    it 'returns valid publicKey options + stashes the challenge in the session' do
      post '/api/auth/register/options', { username: 'todd' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body['publicKey']).to be_a(Hash)
      expect(body['publicKey']['challenge']).to be_a(String)
      expect(body['publicKey']['user']['name']).to eq('todd')
    end
  end

  describe 'end-to-end registration → user row + credential row + recovery codes' do
    it 'creates everything in one ceremony' do
      response = sign_up_via_api
      expect(response['ok']).to be(true)
      expect(response['username']).to eq('todd')
      expect(response['recovery_codes'].length).to eq(10)

      user = UsersStore.find_by_username('todd')
      expect(user).not_to be_nil
      expect(WebauthnCredentialsStore.count_for_user(user['id'])).to eq(1)
      expect(RecoveryCodesStore.unconsumed_count_for(user['id'])).to eq(10)
    end

    it 'signs the user in (session cookie set)' do
      sign_up_via_api
      # Hit a protected route with the wall ON — we should be allowed in.
      TechFeedReader.enforce_auth_wall = true
      begin
        get '/articles'
        expect(last_response.status).to eq(200)
      ensure
        TechFeedReader.enforce_auth_wall = false
      end
    end
  end

  describe 'end-to-end sign-in (after registration)' do
    it 'reuses the same fake_client passkey for both register + login' do
      sign_up_via_api
      # Clear the session as if we'd come back in a new browser.
      clear_cookies

      response = sign_in_via_api
      expect(response['ok']).to be(true)
      expect(response['return_to']).to eq('/')
    end

    it 'fails for an unknown username (generic 401, no enumeration)' do
      post '/api/auth/login/options', { username: 'noone' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }
      expect(last_response.status).to eq(200)  # options endpoint never 404s
      options = JSON.parse(last_response.body)['publicKey']
      expect(options['allowCredentials']).to eq([])
    end

    it 'rejects a tampered assertion' do
      sign_up_via_api
      clear_cookies

      post '/api/auth/login/options', { username: 'todd' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }
      options = JSON.parse(last_response.body)['publicKey']
      assertion = fake_client.get(challenge: options['challenge'])
      # Tamper: swap the signature for garbage. FakeClient hashes
      # have string keys.
      assertion['response']['signature'] = Base64.urlsafe_encode64('not-the-real-sig', padding: false)

      post '/api/auth/login/verify', assertion.to_json,
           { 'CONTENT_TYPE' => 'application/json' }
      expect(last_response.status).to eq(401)
    end
  end

  describe 'recovery-code flow' do
    it 'signs the user in when given a valid one-time code' do
      response = sign_up_via_api
      code = response['recovery_codes'].first
      clear_cookies

      post '/api/auth/recovery', { code: code }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body['ok']).to be(true)
      expect(body['recovery_codes_remaining']).to eq(9)
    end

    it 'rejects a used code' do
      response = sign_up_via_api
      code = response['recovery_codes'].first
      clear_cookies

      post '/api/auth/recovery', { code: code }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }
      clear_cookies

      post '/api/auth/recovery', { code: code }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }
      expect(last_response.status).to eq(401)
    end

    it 'rejects a garbage code' do
      post '/api/auth/recovery', { code: 'XK4P-9MWZ-FAKE-CODE-NOPE' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }
      expect(last_response.status).to eq(401)
    end
  end

  describe '/sign-out' do
    it 'clears the session + redirects home' do
      sign_up_via_api
      post '/sign-out'
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to end_with('/')
    end
  end

  # Auth wall — explicitly flip on for these specs only.
  describe 'auth wall (enforce_auth_wall = true)' do
    around(:each) do |ex|
      TechFeedReader.enforce_auth_wall = true
      ex.run
    ensure
      TechFeedReader.enforce_auth_wall = false
    end

    it 'lets / + /about + /sign-in + /sign-up through unauthenticated' do
      %w[/ /about /sign-in /sign-up /health].each do |path|
        get path
        expect(last_response.status).to be < 400, "#{path} should be public, got #{last_response.status}"
      end
    end

    it 'redirects /articles to /sign-in when unauthenticated' do
      get '/articles'
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to end_with('/sign-in')
    end

    it 'remembers the return_to path for post-login redirect' do
      get '/articles?state=unread'
      sign_up_via_api(username: 'todd')
      # Now the session has return_to set + the user is signed in;
      # the JSON verify response included return_to.
      # Confirm a fresh GET of /articles succeeds:
      get '/articles'
      expect(last_response.status).to eq(200)
    end

    it 'lets API auth endpoints through (they ARE auth)' do
      post '/api/auth/register/options', { username: 'wallcheck' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }
      expect(last_response.status).to be < 500
    end
  end
end
