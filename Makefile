.PHONY: run dev serve test install migrate seed-feeds refresh-feeds refresh-feed scheduler sidekiq redis jaeger jaeger-stop serve-otel sidekiq-otel run-all stop-all digest prune

install:
	bundle install

# Apply any pending SQL migrations from db/migrations/. Idempotent — safe
# to run repeatedly. The web app auto-migrates on boot (see app/main.rb)
# so this is mostly for CI / setup steps that prep the DB before the
# scheduler or scripts run.
migrate:
	bundle exec ruby scripts/migrate.rb

# Insert the v1-kickoff starter feeds (HN, Lobsters, Ars, Verge,
# simonwillison.net). Idempotent — skips any URL already present.
seed-feeds:
	bundle exec ruby scripts/seed_feeds.rb

# Auto-reloading dev server. `rerun` reads .rerun in the project root for
# watch dirs, file patterns, and ignore globs. NOTE: .rerun does NOT support
# `#` comments — its contents are shell-split verbatim, so any `#` becomes a
# literal token (and any prose with quotes/punctuation can be misparsed as
# options). Keep .rerun option-only; document choices here instead:
#   --dir app,views,public,scripts   only watch source directories
#   --pattern *.{rb,erb,js,css,...}  narrower than rerun's default; ignores .md
#   --ignore data/* tmp/* .cache/*   skip cache + state writes (no thrashing)
# `make dev` is an alias kept for muscle memory.
run dev:
	bundle exec rerun 'ruby app/main.rb'

# Plain server with no auto-reload — rare, e.g. when profiling startup time.
serve:
	bundle exec ruby app/main.rb

test:
	bundle exec rspec

# Poll every feed in FeedsStore once. Honours per-feed ETag / Last-Modified
# so feeds that support 304 don't waste bandwidth.
refresh-feeds:
	bundle exec ruby scripts/refresh_feeds.rb

# Refresh a single feed: make refresh-feed FEED=<id-or-url>
refresh-feed:
	bundle exec ruby scripts/refresh_feed.rb $(FEED)

# Long-running poller — reads FeedsStore on each tick, picks feeds whose
# next_fetch_at has passed, fetches them, repeats. Schedule via launchd /
# systemd so it auto-restarts; or run under tmux during dev.
scheduler:
	bundle exec ruby scripts/scheduler.rb $(OPTS)

# Background worker — pops FeedRefreshWorker jobs off Redis and runs the
# fetch + sanitize + import. Required for the header refresh button to
# do anything (without it the job sits in the queue). Concurrency 5 is
# plenty for a single-user app; bump with -c if you add more workers.
# Needs Redis listening on REDIS_URL (default redis://localhost:6379/0).
sidekiq:
	bundle exec sidekiq -r ./app/sidekiq_boot.rb -c 5

# Convenience: start a foreground Redis if you don't already have one
# running. macOS users typically `brew services start redis` instead so
# it auto-starts on login; this target is for ad-hoc dev sessions.
redis:
	redis-server

# Local OpenTelemetry collector + UI — the Jaeger all-in-one image
# bundles an OTLP receiver, in-memory storage, and the Jaeger UI in a
# single container. Listens on :4318 (OTLP/HTTP, what the Ruby exporter
# speaks by default), :4317 (OTLP/gRPC), and :16686 (UI).
#
# `docker rm -f` first so re-running this target is safe even if a
# previous container is still around. Storage is in-memory, so each
# restart wipes the trace history — fine for dev. Browse traces at
# http://localhost:16686 (pick "tech-feed-reader" from the Service
# dropdown). Pair with `make serve-otel` / `make sidekiq-otel`.
jaeger:
	docker rm -f jaeger >/dev/null 2>&1 || true
	docker run -d --name jaeger \
	  -p 16686:16686 -p 4317:4317 -p 4318:4318 \
	  jaegertracing/all-in-one:latest
	@echo ''
	@echo 'Jaeger UI:  http://localhost:16686'
	@echo 'OTLP/HTTP:  http://localhost:4318  (set OTEL_EXPORTER_OTLP_ENDPOINT to this)'

jaeger-stop:
	docker rm -f jaeger >/dev/null 2>&1 || true
	@echo 'jaeger container removed'

# Boot the web app with the OTLP exporter pointed at the local Jaeger
# from `make jaeger`. The Tracing module flips otlp_enabled? on once
# OTEL_EXPORTER_OTLP_ENDPOINT is set, installing the BatchSpanProcessor
# alongside the in-memory recorder — both run, so /admin/traces still
# works and Jaeger gets a copy.
serve-otel:
	OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 \
	OTEL_SERVICE_NAME=tech-feed-reader \
	bundle exec ruby app/main.rb

# Same wiring for the Sidekiq worker process — feed.fetch + llm.summarize
# manual spans fire from the worker, so without this the only thing in
# Jaeger is web traffic.
sidekiq-otel:
	OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 \
	OTEL_SERVICE_NAME=tech-feed-reader \
	bundle exec sidekiq -r ./app/sidekiq_boot.rb -c 5

# One-shot dev session: starts Jaeger, Redis (if not already up), the web
# app, and the Sidekiq worker — all in the background — then opens
# browser tabs to the app and Jaeger UI. PIDs in tmp/pids/, logs in
# tmp/logs/. Idempotent: re-running detects already-running processes
# and skips. Set SKIP_JAEGER=1 to skip the Docker step.
run-all:
	@./scripts/run_all.sh

# Symmetric teardown for `make run-all`. Sends SIGTERM, waits 8s for a
# graceful exit, then SIGKILL. Only stops the Redis it started itself
# (a pre-existing brew-services Redis is left alone). Removes the
# Jaeger container.
stop-all:
	@./scripts/stop_all.sh

# Compose + persist a digest snapshot. Pulls every unread article
# whose published_at is within the last DIGEST_WINDOW_HOURS (default
# 24), joins each row to its cached summary (LLM > extractive >
# excerpt), and inserts a row into the digests table. Browse the
# stored digests at /digests in the web app. Wire to cron / launchd
# to fire daily — see scripts/generate_digest.rb for an example
# crontab entry.
digest:
	bundle exec ruby scripts/generate_digest.rb

# Retention sweep — delete articles older than RETENTION_DAYS (default
# 7). Bookmarked articles are always preserved; set PRUNE_KEEP_UNREAD=1
# to also keep unread items past the window. Cascades clean up
# read_state, summaries, article_tags, and the articles_fts index.
# `make refresh-feeds` calls this automatically at the end of every
# refresh cycle (override with PRUNE_ON_REFRESH=0).
prune:
	bundle exec ruby scripts/prune_articles.rb

# Cosmetics 6 — sweep podcast feeds whose image_url is null/empty
# and try to fill it via the iTunes Search API. Idempotent; safe to
# re-run after adding new podcasts. See app/providers/itunes_lookup.rb.
backfill-podcast-images:
	bundle exec ruby scripts/backfill_podcast_images.rb
