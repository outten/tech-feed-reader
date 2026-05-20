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

# STUFF #49 — admin Basic Auth gate is fail-closed in production:
# an unset ADMIN_USERNAME / ADMIN_PASSWORD pair means nobody can
# reach /admin/*. Tests need /admin/* to be reachable so existing
# admin-route specs keep working; spec_helper seeds known creds.
# Specs that exercise the gate explicitly use Rack::Test's
# `basic_authorize` (or delete the env vars + assert 401).
ENV['ADMIN_USERNAME']    ||= 'spec-admin'
ENV['ADMIN_PASSWORD']    ||= 'spec-password'

# PG is the only supported backend (STUFF #47, SQLite removed). The
# suite requires TEST_DATABASE_URL pointed at a disposable database;
# the docker-compose `db` service is the local default. Any
# DATABASE_URL inherited from the developer's shell/.env is replaced
# by TEST_DATABASE_URL so a stray production-pointing var can't
# hijack the suite.
test_url = ENV['TEST_DATABASE_URL']
if test_url.nil? || test_url.empty?
  abort <<~MSG
    spec_helper: TEST_DATABASE_URL is required.

    Local dev: `docker compose up -d db` then export
      TEST_DATABASE_URL=postgres://postgres:postgres@localhost:5432/tfr_test
    (or your own throwaway database).

    CI sets this for you.
  MSG
end
ENV['DATABASE_URL'] = test_url

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

  # Per-run schema bootstrap: drop + recreate the public schema so
  # the suite never inherits cruft from a prior failed run, then
  # apply migrations once. The before(:each) hook reuses the schema
  # via TRUNCATE; if a spec calls Database.reset! (e.g. the adapter-
  # boot test), the hook re-migrates automatically.
  c.before(:suite) do
    Database.connection.execute_batch('DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;')
    Database.migrate!
  end

  c.before(:each) do
    # Fast reset path: TRUNCATE every public table except
    # schema_migrations, RESTART IDENTITY to reset BIGSERIAL
    # sequences, CASCADE through FKs.
    tables = Database.connection
      .execute("SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename <> 'schema_migrations'")
      .map { |r| r['tablename'] }
    if tables.empty?
      # Schema got nuked (e.g. by a spec that resets the connection); reapply.
      Database.migrate!
    else
      quoted = tables.map { |t| %("#{t}") }.join(', ')
      Database.connection.execute("TRUNCATE TABLE #{quoted} RESTART IDENTITY CASCADE")
    end
    HealthRegistry.reset!
    # Seed the default test user. Routes auto-sign-in (1, 't-money')
    # when the auth wall is off (the test-env default).
    Database.connection.execute(
      "INSERT INTO users(id, username, display_name) VALUES (1, 't-money', 't-money') ON CONFLICT DO NOTHING"
    )
    # TRUNCATE … RESTART IDENTITY reset users_id_seq to 1, but the
    # explicit id=1 insert above didn't consume the sequence — bump
    # past it so the next UsersStore.create doesn't collide.
    Database.connection.execute(
      "SELECT setval('users_id_seq', GREATEST(1, (SELECT MAX(id) FROM users)))"
    )

    # STUFF #49 — auto-set the Basic Auth Authorization header for
    # specs that include Rack::Test::Methods, so the existing
    # admin-route specs (10+ files) keep working without per-spec
    # `basic_authorize` boilerplate. Specs that exercise the gate
    # itself override this header (or use wrong credentials) inside
    # their own `before` block.
    if respond_to?(:basic_authorize)
      basic_authorize 'spec-admin', 'spec-password'
    end
  end

  c.after(:each) do
    HealthRegistry.reset!
  end
end
