require_relative 'spec_helper'
require 'webauthn/fake_client'
require_relative '../app/main'
require_relative '../app/users_store'
require_relative '../app/webauthn_credentials_store'
require_relative '../app/recovery_codes_store'

# STUFF #29 follow-up — Account management page.
# Covers display-name editing, passkey list / add / revoke (with
# lockout protection), recovery-code regeneration, and account
# deletion (with typed-username confirmation gate).

RSpec.describe 'Account management routes' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  let(:fake_client) { WebAuthn::FakeClient.new(ENV['WEBAUTHN_ORIGIN']) }

  # Drive the full sign-up flow so the test starts from a logged-in
  # state with one passkey + 10 recovery codes already minted.
  def sign_up_via_api(username: 'todd', display_name: 'Todd')
    post '/api/auth/register/options', { username: username, display_name: display_name }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }
    options = JSON.parse(last_response.body)['publicKey']
    attestation = fake_client.create(challenge: options['challenge'])
    post '/api/auth/register/verify', attestation.to_json,
         { 'CONTENT_TYPE' => 'application/json' }
    JSON.parse(last_response.body)
  end

  describe 'GET /account (auth wall)' do
    around do |ex|
      TechFeedReader.enforce_auth_wall = true
      ex.run
    ensure
      TechFeedReader.enforce_auth_wall = false
    end

    it 'redirects unauthenticated visitors to /sign-in' do
      get '/account'
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to include('/sign-in')
    end

    it 'renders the account page for signed-in users with profile + passkey + recovery sections' do
      sign_up_via_api
      get '/account'
      expect(last_response.status).to eq(200)
      body = last_response.body
      expect(body).to include('Profile')
      expect(body).to include('Passkeys')
      expect(body).to include('Recovery codes')
      expect(body).to include('Delete account')
      # The signed-in user's username is shown in the header copy.
      expect(body).to include('<strong>todd</strong>')
      # One passkey rendered + 10 recovery codes left.
      expect(body).to match(/\(1\)/)
      expect(body).to include('10')
    end
  end

  describe 'POST /account/display-name' do
    before { sign_up_via_api(username: 'todd', display_name: 'Todd') }

    it 'updates the user\'s display name and redirects with a notice' do
      post '/account/display-name', display_name: 'Toddster'
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to include('notice=display-name-updated')
      user = UsersStore.find_by_username('todd')
      expect(user['display_name']).to eq('Toddster')
    end

    it 'falls back to username when display_name is blank' do
      post '/account/display-name', display_name: '   '
      user = UsersStore.find_by_username('todd')
      expect(user['display_name']).to eq('todd')
    end

    it 'caps display name length at 80 chars' do
      post '/account/display-name', display_name: 'x' * 200
      user = UsersStore.find_by_username('todd')
      expect(user['display_name'].length).to eq(80)
    end
  end

  describe 'POST /account/passkey/:credential_id/delete' do
    let!(:signup_data) { sign_up_via_api }
    let(:user) { UsersStore.find_by_username('todd') }
    let(:credential_id) { WebauthnCredentialsStore.for_user(user['id']).first['credential_id'] }

    it 'refuses to revoke the last passkey when zero unused recovery codes remain' do
      # Burn all 10 recovery codes so the lockout guard kicks in.
      signup_data['recovery_codes'].each { |code| RecoveryCodesStore.consume!(code) }
      expect(RecoveryCodesStore.unconsumed_count_for(user['id'])).to eq(0)
      expect(WebauthnCredentialsStore.count_for_user(user['id'])).to eq(1)

      post "/account/passkey/#{credential_id}/delete"
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to include('error=last-passkey-no-recovery')
      # Passkey still present — not deleted.
      expect(WebauthnCredentialsStore.count_for_user(user['id'])).to eq(1)
    end

    it 'allows revoking the last passkey when recovery codes are still available' do
      post "/account/passkey/#{credential_id}/delete"
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to include('notice=passkey-revoked')
      expect(WebauthnCredentialsStore.count_for_user(user['id'])).to eq(0)
    end

    it 'returns a not-found error for a credential_id that does not belong to this user' do
      post '/account/passkey/totally-bogus-credential-id/delete'
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to include('error=passkey-not-found')
    end
  end

  describe 'POST /account/recovery-codes/regenerate' do
    before { sign_up_via_api }
    let(:user) { UsersStore.find_by_username('todd') }

    it 'wipes the old batch and mints a fresh 10' do
      old_count = RecoveryCodesStore.unconsumed_count_for(user['id'])
      expect(old_count).to eq(10)

      post '/account/recovery-codes/regenerate'
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to include('notice=recovery-codes-regenerated')
      expect(RecoveryCodesStore.unconsumed_count_for(user['id'])).to eq(10)
    end

    it 'surfaces the new plaintext codes once on the next GET /account' do
      post '/account/recovery-codes/regenerate'
      follow_redirect!
      body = last_response.body
      # Codes use the BASE32 alphabet with 5 groups of 4 chars separated by dashes.
      expect(body).to match(/[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}/)
      expect(body).to include("Save these now")

      # Second GET — codes are NOT re-shown.
      get '/account'
      expect(last_response.body).not_to include('Save these now')
    end
  end

  describe 'POST /account/delete' do
    before { sign_up_via_api(username: 'todd') }
    let(:user) { UsersStore.find_by_username('todd') }

    it 'refuses when the typed username is missing' do
      uid = user['id']
      post '/account/delete'
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to include('error=delete-confirm-mismatch')
      expect(UsersStore.find(uid)).not_to be_nil
    end

    it 'refuses when the typed username does not match' do
      uid = user['id']
      post '/account/delete', confirm_username: 'someone-else'
      expect(last_response.headers['Location']).to include('error=delete-confirm-mismatch')
      expect(UsersStore.find(uid)).not_to be_nil
    end

    it 'is case-insensitive on the typed confirmation (matches normalized username)' do
      uid = user['id']
      post '/account/delete', confirm_username: 'TODD'
      expect(last_response.headers['Location']).to include('notice=account-deleted')
      expect(UsersStore.find(uid)).to be_nil
    end

    it 'deletes the user and cascades to per-user tables (webauthn, recovery codes)' do
      uid = user['id']
      expect(WebauthnCredentialsStore.count_for_user(uid)).to eq(1)
      expect(RecoveryCodesStore.unconsumed_count_for(uid)).to eq(10)

      post '/account/delete', confirm_username: 'todd'
      expect(UsersStore.find(uid)).to be_nil
      # The FK CASCADE on webauthn_credentials.user_id → users.id wiped both.
      expect(WebauthnCredentialsStore.count_for_user(uid)).to eq(0)
      expect(RecoveryCodesStore.unconsumed_count_for(uid)).to eq(0)
    end

    it 'signs the user out and redirects to / with a notice' do
      post '/account/delete', confirm_username: 'todd'
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to include('notice=account-deleted')
      # Subsequent /account hit (with the wall on) must redirect to sign-in.
      TechFeedReader.enforce_auth_wall = true
      begin
        get '/account'
        expect(last_response.status).to eq(302)
        expect(last_response.headers['Location']).to include('/sign-in')
      ensure
        TechFeedReader.enforce_auth_wall = false
      end
    end
  end

  describe 'POST /account/passkey/options + /verify (add another passkey)' do
    before { sign_up_via_api }
    let(:user) { UsersStore.find_by_username('todd') }

    it 'returns options scoped to the signed-in user (no username needed in body)' do
      post '/account/passkey/options', '{}', { 'CONTENT_TYPE' => 'application/json' }
      expect(last_response.status).to eq(200)
      data = JSON.parse(last_response.body)
      expect(data['publicKey']).to be_a(Hash)
      expect(data['publicKey']['challenge']).to be_a(String)
    end

    it 'registers a second passkey on the same account through verify' do
      expect(WebauthnCredentialsStore.count_for_user(user['id'])).to eq(1)

      post '/account/passkey/options', '{}', { 'CONTENT_TYPE' => 'application/json' }
      options = JSON.parse(last_response.body)['publicKey']
      attestation = fake_client.create(challenge: options['challenge'])
      post '/account/passkey/verify', attestation.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)['ok']).to be(true)
      expect(WebauthnCredentialsStore.count_for_user(user['id'])).to eq(2)
    end
  end

  describe 'header chip becomes a link to /account' do
    it 'renders the chip as <a href="/account"> for signed-in users' do
      sign_up_via_api
      get '/articles'
      expect(last_response.body).to match(%r{<a href="/account" class="auth-chip"})
    end
  end
end
