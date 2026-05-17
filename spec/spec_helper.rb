require 'rspec'
require 'rack/test'

ENV['RACK_ENV'] = 'test'

# Phase A1 (consumer auth). Set the env vars the app boot needs
# BEFORE any app file requires them. Tests don't read .env (the
# dotenv branch in Credentials.load! now actually skips in test
# env), so we must inject deterministic values here.
ENV['SESSION_SECRET']    ||= '0' * 128
ENV['WEBAUTHN_RP_NAME']  ||= 'Tech Feed Reader (test)'
ENV['WEBAUTHN_RP_ID']    ||= 'localhost'
ENV['WEBAUTHN_ORIGIN']   ||= 'http://localhost:4567'

# Phase 5 / D-PG-2. The test suite defaults to SQLite :memory: so
# `bundle exec rspec` works on any laptop without a running PG
# server. Opt into the PG path by setting TEST_DATABASE_URL — used
# by the CI matrix's postgres job. Any DATABASE_URL inherited from
# the developer's shell/.env is explicitly cleared so a stray
# postgres://... pointing at a personal DB doesn't quietly hijack
# the suite.
if (test_url = ENV['TEST_DATABASE_URL'])
  ENV['DATABASE_URL'] = test_url
else
  ENV.delete('DATABASE_URL')
end

require_relative '../app/database'
require_relative '../app/health_registry'
require_relative '../app/users_store'

# Reset + re-migrate the in-memory DB before every example so each spec
# starts from a clean, schema-loaded slate. database_spec layers its own
# Database.reset! on top to test the migrator itself; that's compatible —
# resetting closes the (in-memory) connection, the test body then opens
# a fresh empty DB and exercises migrate! from scratch.
#
# Phase A2 — every example also seeds the default test user
# (id=1, username='t-money'). Routes auto-sign-in this user when the
# auth wall is off (the test-env default), so the per-user store calls
# always have a real user_id to scope to. Specs that exercise auth
# directly (auth_spec) clear cookies and sign their own users in.
RSpec.configure do |c|
  c.color = true
  c.formatter = :documentation

  c.before(:each) do
    Database.reset!
    Database.migrate!
    HealthRegistry.reset!
    # Migration 022 already seeds (1, 't-money'); OR IGNORE keeps this
    # safe across "fresh schema" + "migrations already ran" specs.
    Database.connection.execute(
      "INSERT OR IGNORE INTO users(id, username, display_name) VALUES (1, 't-money', 't-money')"
    )
  end

  c.after(:each) do
    Database.reset!
    HealthRegistry.reset!
  end
end
