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

  # Per-run schema bootstrap. Migrate once at suite startup so the
  # per-spec hook can stay cheap (TRUNCATE on PG, in-memory rebuild
  # on SQLite). The before(:each) hook still checks for schema
  # existence so re-runs after `Database.reset!` (e.g. the adapter-
  # switch test in pg_adapter_spec) automatically remigrate.
  c.before(:suite) do
    if Database.adapter == :postgres
      # Hermetic across runs: drop + recreate so we never inherit
      # cruft from a prior failed run.
      Database.connection.execute_batch('DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;')
      Database.migrate!
    end
  end

  c.before(:each) do
    if Database.adapter == :postgres
      # Fast reset path: TRUNCATE every public table except
      # schema_migrations, RESTART IDENTITY to reset BIGSERIAL
      # sequences, CASCADE through FKs. ~100x cheaper than rerunning
      # the full 372-line 001_init.sql migration on every example
      # (was ~45s of the prior 57s PG suite runtime).
      tables = Database.connection
        .execute("SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename <> 'schema_migrations'")
        .map { |r| r['tablename'] }
      if tables.empty?
        # Schema got nuked (e.g. by the adapter-switch test that
        # resets the connection); reapply.
        Database.migrate!
      else
        quoted = tables.map { |t| %("#{t}") }.join(', ')
        Database.connection.execute("TRUNCATE TABLE #{quoted} RESTART IDENTITY CASCADE")
      end
    else
      Database.reset!
      Database.migrate!
    end
    HealthRegistry.reset!
    # Migration 022 seeds (1, 't-money') on SQLite via INSERT OR IGNORE.
    # The PG consolidated migration doesn't seed it (the migration
    # itself shouldn't know about test fixtures); seed here for both
    # backends using ANSI ON CONFLICT (works under SQLite 3.24+ too).
    Database.connection.execute(
      "INSERT INTO users(id, username, display_name) VALUES (1, 't-money', 't-money') ON CONFLICT DO NOTHING"
    )
    if Database.adapter == :postgres
      # TRUNCATE … RESTART IDENTITY already reset users_id_seq to 1,
      # but the t-money seed above inserted id=1 with explicit value
      # without consuming the sequence — bump past it so the next
      # UsersStore.create doesn't collide.
      Database.connection.execute(
        "SELECT setval('users_id_seq', GREATEST(1, (SELECT MAX(id) FROM users)))"
      )
    end
  end

  c.after(:each) do
    # SQLite uses an in-memory DB; reset! drops the handle and the
    # next before(:each)'s migrate! rebuilds from scratch. Cheap.
    # PG keeps the connection — the next before(:each)'s TRUNCATE
    # handles state, no reset! needed (and the reset+reconnect was
    # most of the prior per-spec cost).
    Database.reset! if Database.adapter == :sqlite
    HealthRegistry.reset!
  end
end
