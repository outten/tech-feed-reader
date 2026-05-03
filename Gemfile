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

# Config
gem 'dotenv'
gem 'ostruct'

# Feed parsing — feedjira normalises RSS 2.0 / RSS 1.0 / Atom into a single
# shape so we don't ship three parsers. Pulls in nokogiri as a dependency.
gem 'feedjira'

# HTML sanitization for the reading view — strip <script>, <iframe>,
# on-* event handlers before rendering article content.
gem 'loofah'

# csv is no longer a default gem starting with Ruby 3.4; needed if/when we
# add export endpoints. Cheap to ship now so it's there when Tier 3 lands.
gem 'csv'

# SQLite — single source of truth for feeds, articles, read state, tags,
# and summaries. FTS5 (built into modern sqlite) backs /search. WAL mode
# is enabled in app/database.rb so the scheduler can write while the web
# process serves reads without blocking.
gem 'sqlite3'

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

# Pin connection_pool to the 2.x line — Sidekiq 7.3 declares
# `connection_pool >= 2.3.0` but is incompatible with the 3.x rewrite
# (Sidekiq::Scheduled::Poller#initial_wait calls TimedStack#pop with a
# timeout arg, which 3.0 dropped). Without this pin Bundler picks up
# 3.x and the scheduled-job poller crashes on boot.
gem 'connection_pool', '~> 2.4'
