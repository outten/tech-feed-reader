require 'rspec'
require 'rack/test'

ENV['RACK_ENV'] = 'test'

# Phase A1 (consumer auth). Set the env vars the app boot needs
# BEFORE any app file requires them. Tests don't read .env (the
# dotenv branch in main.rb skips loading in test env), so we must
# inject deterministic values here.
ENV['SESSION_SECRET']    ||= '0' * 128
ENV['WEBAUTHN_RP_NAME']  ||= 'Tech Feed Reader (test)'
ENV['WEBAUTHN_RP_ID']    ||= 'localhost'
ENV['WEBAUTHN_ORIGIN']   ||= 'http://localhost:4567'

require_relative '../app/database'
require_relative '../app/health_registry'

# Reset + re-migrate the in-memory DB before every example so each spec
# starts from a clean, schema-loaded slate. database_spec layers its own
# Database.reset! on top to test the migrator itself; that's compatible —
# resetting closes the (in-memory) connection, the test body then opens
# a fresh empty DB and exercises migrate! from scratch.
RSpec.configure do |c|
  c.color = true
  c.formatter = :documentation

  c.before(:each) do
    Database.reset!
    Database.migrate!
    HealthRegistry.reset!
  end

  c.after(:each) do
    Database.reset!
    HealthRegistry.reset!
  end
end
