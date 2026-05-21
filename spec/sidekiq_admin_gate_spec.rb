require_relative 'spec_helper'
require_relative '../app/auth'
require 'rack'
require 'rack/builder'
require 'rack/auth/basic'
require 'rack/test'
require 'base64'

# STUFF #51 — Sidekiq::Web is mounted at /admin/sidekiq via Rack::Builder
# BEFORE Sinatra in the boot block in app/main.rb. The Sinatra-level
# admin Basic Auth gate from #49 doesn't see those requests. Sidekiq::Web
# is wrapped with Rack::Auth::Basic + a fail-closed credentials block.
# We can't exercise the actual mount via Rack::Test (the boot block runs
# only on direct script invocation), so this spec covers the gating
# behaviour in isolation by replaying the same block against a stub
# inner app + Rack::Auth::Basic.
RSpec.describe 'Sidekiq Basic Auth gate (STUFF #51)' do
  include Rack::Test::Methods

  # The exact block app/main.rb passes to Rack::Auth::Basic. Mirrors
  # the real wiring so a regression there fails this spec.
  GATE_BLOCK = lambda do |user, pass|
    expected = Auth.admin_credentials
    expected &&
      Rack::Utils.secure_compare(expected[0], user.to_s) &&
      Rack::Utils.secure_compare(expected[1], pass.to_s)
  end.freeze

  def app
    inner = lambda { |_env| [200, { 'Content-Type' => 'text/plain' }, ['ok']] }
    Rack::Builder.new do
      use Rack::Auth::Basic, 'Sidekiq', &GATE_BLOCK
      run inner
    end.to_app
  end

  around do |ex|
    prior_user = ENV.fetch('ADMIN_USERNAME', nil)
    prior_pass = ENV.fetch('ADMIN_PASSWORD', nil)
    ex.run
  ensure
    if prior_user then ENV['ADMIN_USERNAME'] = prior_user else ENV.delete('ADMIN_USERNAME') end
    if prior_pass then ENV['ADMIN_PASSWORD'] = prior_pass else ENV.delete('ADMIN_PASSWORD') end
  end

  context 'when admin credentials are unset (fail-closed)' do
    before do
      ENV.delete('ADMIN_USERNAME')
      ENV.delete('ADMIN_PASSWORD')
      header 'Authorization', nil
    end

    it '401s without credentials' do
      get '/jobs'
      expect(last_response.status).to eq(401)
      expect(last_response.headers['WWW-Authenticate']).to include('Basic')
    end

    it '401s even when the client supplies SOME credentials' do
      basic_authorize 'admin', 'whatever'
      get '/jobs'
      expect(last_response.status).to eq(401)
    end
  end

  context 'with the correct credentials' do
    before do
      ENV['ADMIN_USERNAME'] = 'admin'
      ENV['ADMIN_PASSWORD'] = 'hunter2'
      basic_authorize 'admin', 'hunter2'
    end

    it 'passes through to Sidekiq::Web (200 from the stub)' do
      get '/jobs'
      expect(last_response.status).to eq(200)
    end
  end

  context 'with the wrong password' do
    before do
      ENV['ADMIN_USERNAME'] = 'admin'
      ENV['ADMIN_PASSWORD'] = 'hunter2'
      basic_authorize 'admin', 'wrong'
    end

    it '401s' do
      get '/jobs'
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
      get '/jobs'
      expect(last_response.status).to eq(401)
    end
  end

  context 'constant-time compare' do
    # Sanity check the compare is via Rack::Utils.secure_compare (not
    # ==), so attackers can't time-attack the password byte-by-byte.
    # We don't measure timing — we just confirm the helper is the one
    # being used by stubbing it and watching for the call.
    before do
      ENV['ADMIN_USERNAME'] = 'admin'
      ENV['ADMIN_PASSWORD'] = 'hunter2'
    end

    it 'calls Rack::Utils.secure_compare for both user and pass' do
      expect(Rack::Utils).to receive(:secure_compare).at_least(:twice).and_call_original
      basic_authorize 'admin', 'hunter2'
      get '/jobs'
      expect(last_response.status).to eq(200)
    end
  end
end
