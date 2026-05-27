source 'https://rubygems.org'

# Web framework
gem 'sinatra'
gem 'puma'
gem 'rerun'

# Rack 3 unbundled the `rackup` CLI into its own gem; Sinatra 4 + Rack 3
# need it explicit or `bundle exec ruby app/main.rb` fails to boot.
gem 'rackup', '~> 2.3'

# Test
group :test do
  gem 'rspec'
  gem 'rack-test'
end

# Dev-only request profiler — injects a small badge in the top-left of
# every HTML response with per-request timing + per-SQL-query breakdown
# (auto-instruments `pg` when loaded). Loaded only in development; not
# bundled into the production image.
group :development do
  gem 'rack-mini-profiler', '~> 3.3'
  # stackprof powers rack-mini-profiler's flamegraph view
  # (`?pp=flamegraph` on any URL). Must be `require`d explicitly —
  # rack-mini-profiler auto-detects it once it's loaded.
  gem 'stackprof'
end

# Config
gem 'dotenv'
gem 'ostruct'

# Auth — WebAuthn server library (passkey-only sign-in, per Phase A1).
# Handles registration + authentication ceremonies, attestation
# verification, sign-count rollback detection. Used by Mastodon + GitLab.
gem 'webauthn'

# Feed parsing — feedjira normalises RSS 2.0 / RSS 1.0 / Atom into a single
# shape so we don't ship three parsers. Pulls in nokogiri as a dependency.
gem 'feedjira'

# HTML sanitization for the reading view — strip <script>, <iframe>,
# on-* event handlers before rendering article content.
gem 'loofah'

# csv is no longer a default gem starting with Ruby 3.4; needed if/when we
# add export endpoints. Cheap to ship now so it's there when Tier 3 lands.
gem 'csv'

# PostgreSQL — single source of truth for feeds, articles, read state,
# tags, summaries, pageviews, and sports data. tsvector + ts_rank back
# /search. Connection string in DATABASE_URL; adapter in
# app/database/pg_adapter.rb.
gem 'pg', '~> 1.5'

# Anthropic SDK — powers the Tier 2-K LLM summary on /article/:uid.
# Optional at boot — if ANTHROPIC_API_KEY is unset the "Summarize with
# Claude" button stays hidden and the existing pure-Ruby extractive
# summary keeps working.
gem 'anthropic'

# Background job runner — used to enqueue feed refresh work so the web
# request that triggered the refresh returns immediately. The worker
# process is started separately via `make sidekiq`. Sidekiq pulls in
# `redis` transitively and connects via REDIS_URL (default
# redis://localhost:6379/0).
gem 'sidekiq', '~> 7.3'

# Recurring background jobs (hourly feed refresh, nightly sports sync).
# Schedule is loaded at sidekiq_boot in the server process only; jobs
# fire via the standard Sidekiq queue + retry pipeline.
gem 'sidekiq-cron', '~> 1.12'

# Pin connection_pool to the 2.x line — Sidekiq 7.3 declares
# `connection_pool >= 2.3.0` but is incompatible with the 3.x rewrite
# (Sidekiq::Scheduled::Poller#initial_wait calls TimedStack#pop with a
# timeout arg, which 3.0 dropped). Without this pin Bundler picks up
# 3.x and the scheduled-job poller crashes on boot.
gem 'connection_pool', '~> 2.4'

# Prometheus client — exposes /metrics in the Prometheus exposition
# format (text/plain; version=0.0.4). Pure-Ruby in-memory registry;
# no external store needed. Registry is process-local, so the web
# process and the worker process each expose their own metrics.
gem 'prometheus-client', '~> 4.2'

# OpenTelemetry — distributed tracing. The SDK only activates when
# OTEL_EXPORTER_OTLP_ENDPOINT is set, so dev runs without an OTel
# collector configured pay zero overhead (the API package returns
# no-op tracers). instrumentation-all auto-instruments Sinatra,
# Rack, Sidekiq, Net::HTTP, and SQLite3; we add manual spans on
# top for FeedFetcher + Summarizer::Claude.
gem 'opentelemetry-sdk',                '~> 1.6'
gem 'opentelemetry-instrumentation-all', '~> 0.78'
gem 'opentelemetry-exporter-otlp',       '~> 0.30'
