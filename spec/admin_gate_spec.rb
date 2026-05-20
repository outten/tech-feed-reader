require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/auth'

# STUFF #49 — admin HTTP Basic Auth gate over /admin/* +
# /api/admin/*. Fail-closed when ADMIN_USERNAME / ADMIN_PASSWORD
# env vars are unset/empty.
RSpec.describe 'Admin Basic Auth gate (STUFF #49)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  around do |ex|
    prior_user = ENV.fetch('ADMIN_USERNAME', nil)
    prior_pass = ENV.fetch('ADMIN_PASSWORD', nil)
    ex.run
  ensure
    if prior_user then ENV['ADMIN_USERNAME'] = prior_user else ENV.delete('ADMIN_USERNAME') end
    if prior_pass then ENV['ADMIN_PASSWORD'] = prior_pass else ENV.delete('ADMIN_PASSWORD') end
  end

  describe 'Auth.admin_credentials' do
    it 'returns the user+pass pair when both env vars are set' do
      ENV['ADMIN_USERNAME'] = 'admin'
      ENV['ADMIN_PASSWORD'] = 'hunter2'
      expect(Auth.admin_credentials).to eq(['admin', 'hunter2'])
    end

    it 'returns nil when either var is unset' do
      ENV.delete('ADMIN_PASSWORD')
      expect(Auth.admin_credentials).to be_nil
    end

    it 'returns nil when either var is empty string' do
      ENV['ADMIN_USERNAME'] = ''
      ENV['ADMIN_PASSWORD'] = 'x'
      expect(Auth.admin_credentials).to be_nil
    end
  end

  describe 'Auth.basic_auth_from' do
    it 'parses a well-formed Authorization header' do
      header = 'Basic ' + Base64.encode64('admin:hunter2').strip
      expect(Auth.basic_auth_from('HTTP_AUTHORIZATION' => header)).to eq(['admin', 'hunter2'])
    end

    it 'returns nil for a missing header' do
      expect(Auth.basic_auth_from({})).to be_nil
    end

    it 'returns nil for a non-Basic scheme' do
      expect(Auth.basic_auth_from('HTTP_AUTHORIZATION' => 'Bearer xyz')).to be_nil
    end

    it 'tolerates passwords containing colons' do
      header = 'Basic ' + Base64.encode64('admin:pa:ss:wo:rd').strip
      expect(Auth.basic_auth_from('HTTP_AUTHORIZATION' => header)).to eq(['admin', 'pa:ss:wo:rd'])
    end
  end

  describe 'Auth.admin_path?' do
    %w[/admin /admin/analytics /admin/users /admin/llm-quota /api/admin/refresh/all].each do |p|
      it "matches #{p}" do
        expect(Auth.admin_path?(p)).to be(true)
      end
    end

    %w[/articles /sports /feeds /api/articles /admin-not-really].each do |p|
      it "does NOT match #{p}" do
        expect(Auth.admin_path?(p)).to be(false)
      end
    end
  end

  describe 'before-filter gate' do
    context 'when credentials are unset (fail-closed)' do
      before do
        ENV.delete('ADMIN_USERNAME')
        ENV.delete('ADMIN_PASSWORD')
        # Cancel the spec_helper's auto-authorize so this case truly
        # has no admin creds.
        header 'Authorization', nil
      end

      it '401s on /admin even though the WebAuthn wall is satisfied' do
        get '/admin'
        expect(last_response.status).to eq(401)
        expect(last_response.headers['WWW-Authenticate']).to include('Basic')
      end

      it '401s on /admin/analytics + /admin/users + /api/admin/* too' do
        %w[/admin/analytics /admin/users /api/admin/refresh/all].each do |p|
          get p
          expect(last_response.status).to eq(401), "#{p} did not 401"
        end
      end

      it 'lets non-admin paths through normally' do
        get '/articles'
        expect(last_response.status).not_to eq(401)
      end
    end

    context 'with the correct credentials' do
      before do
        ENV['ADMIN_USERNAME'] = 'admin'
        ENV['ADMIN_PASSWORD'] = 'hunter2'
        basic_authorize 'admin', 'hunter2'
      end

      it 'lets /admin through with 200' do
        get '/admin'
        expect(last_response.status).to eq(200)
      end

      it 'lets /admin/users through with 200' do
        get '/admin/users'
        expect(last_response.status).to eq(200)
      end
    end

    context 'with the wrong password' do
      before do
        ENV['ADMIN_USERNAME'] = 'admin'
        ENV['ADMIN_PASSWORD'] = 'hunter2'
        basic_authorize 'admin', 'guess'
      end

      it '401s' do
        get '/admin'
        expect(last_response.status).to eq(401)
      end
    end

    context 'with the wrong username' do
      before do
        ENV['ADMIN_USERNAME'] = 'admin'
        ENV['ADMIN_PASSWORD'] = 'hunter2'
        basic_authorize 'guest', 'hunter2'
      end

      it '401s' do
        get '/admin'
        expect(last_response.status).to eq(401)
      end
    end
  end

  describe 'logout / re-login flow' do
    before do
      ENV['ADMIN_USERNAME'] = 'admin'
      ENV['ADMIN_PASSWORD'] = 'hunter2'
      basic_authorize 'admin', 'hunter2'
    end

    it 'lets /admin through before logout' do
      get '/admin'
      expect(last_response.status).to eq(200)
    end

    it 'POST /admin/logout redirects to /admin' do
      post '/admin/logout'
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to end_with('/admin')
    end

    it 'after logout, /admin 401s even with valid cached credentials' do
      post '/admin/logout'
      follow_redirect!
      expect(last_response.status).to eq(401)
      expect(last_response.body).to include('Logged out of admin')
    end

    it 'does NOT send WWW-Authenticate when logged out (avoids infinite re-prompt loop)' do
      # The browser pops a Basic Auth prompt whenever it sees a 401 with
      # WWW-Authenticate. While the logout flag is set the gate rejects
      # ANY credentials, so prompting would trap the user — this assertion
      # locks in the "no prompt while logged out" guarantee.
      post '/admin/logout'
      follow_redirect!
      expect(last_response.status).to eq(401)
      expect(last_response.headers['WWW-Authenticate']).to be_nil
    end

    it 'DOES send WWW-Authenticate when no credentials are present (no logout flag)' do
      # Sanity check the opposite branch: when the flag isn't set, missing
      # credentials should prompt normally.
      header 'Authorization', nil
      get '/admin'
      expect(last_response.status).to eq(401)
      expect(last_response.headers['WWW-Authenticate']).to include('Basic')
    end

    it 'GET /admin/login is exempt from the gate so logged-out users can clear the flag' do
      post '/admin/logout'
      get '/admin/login'
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to end_with('/admin')
    end

    it 'after /admin/login the user is admin again (cached creds re-honoured)' do
      post '/admin/logout'
      get '/admin/login'
      follow_redirect!
      expect(last_response.status).to eq(200)
    end

    it 'POST /admin/logout itself requires admin creds (gate fires)' do
      header 'Authorization', nil
      post '/admin/logout'
      expect(last_response.status).to eq(401)
    end
  end
end
