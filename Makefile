.PHONY: run dev stop serve test install migrate seed-feeds refresh-feeds refresh-feed scheduler sidekiq redis jaeger jaeger-stop serve-otel sidekiq-otel run-all stop-all digest prune release release-major release-minor release-patch _release_guard _release_bump publish-image deploy deploy-major deploy-minor deploy-patch _remote_deploy fix-article-links

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

# Phase A1 (consumer auth) — insert a user row by username. No passkey
# is registered; useful for dev when you've blown away the DB and want
# a known user_id=1 to inherit the existing single-user data. Use:
#   make seed-user USER=todd
# Pass DISPLAY="Full Name" for a custom display name. Falls back to
# username if omitted.
seed-user:
	bundle exec ruby scripts/seed_user.rb $(USER) "$(DISPLAY)"

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

# Stop a `make run` / `make dev` / `make serve` web server. Targets
# the rerun watcher, the Puma child it spawns, and anything else
# listening on port 4567. Idempotent — exits 0 when nothing was
# running, so it's safe to chain (`make stop run`).
stop:
	@pkill -TERM -f 'rerun.*ruby app/main\.rb' 2>/dev/null || true
	@pkill -TERM -f 'ruby app/main\.rb'         2>/dev/null || true
	@pids=`lsof -ti:4567 2>/dev/null`; if [ -n "$$pids" ]; then kill -TERM $$pids 2>/dev/null || true; fi
	@echo "stopped (port 4567 freed if any was running)"

# Plain server with no auto-reload — rare, e.g. when profiling startup time.
serve:
	bundle exec ruby app/main.rb

test:
	@# STUFF #47: spec_helper requires TEST_DATABASE_URL (no silent
	@# fallback to SQLite). Default to the local Postgres tfr_test
	@# database; override with `TEST_DATABASE_URL=... make test` for
	@# a different host. CI sets this in .github/workflows/ci.yml.
	TEST_DATABASE_URL=$${TEST_DATABASE_URL:-postgres://localhost/tfr_test} bundle exec rspec

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

# STUFF #61 — re-sanitize every article's content_html with the
# article's own URL as the absolute-link base. Fixes relative <a>
# and <img> from rows imported before #61 landed. Idempotent;
# already-absolute URLs stay put. DRY_RUN=1 to preview; LIMIT=N to
# sample; VERBOSE=1 to log every changed row.
fix-article-links:
	bundle exec ruby scripts/fix_article_links.rb

# Sports Phase S3 — seed the leagues / teams / follows the user
# cares about (Eagles, Sixers, Union, All Blacks). Idempotent;
# safe to re-run.
seed-sports-data:
	bundle exec ruby scripts/seed_sports_data.rb

# Sports Phase S4 cron entry point — pulls match data from ESPN
# for every followed team. Idempotent; pair with launchd/cron
# for a daily refresh.
sync-sports:
	bundle exec ruby scripts/sync_sports.rb

# AI-assisted triage cron entry point — calls Triage::Claude.run +
# persists the result via TriageStore. One Claude API call per run
# (~$0.02–0.04). Browse stored runs at /triage; detail at /triage/:id.
triage:
	bundle exec ruby scripts/generate_triage.rb

# ---- Release / version bump (STUFF #33A) ------------------------------------
# Three semver-bump targets that gate on a clean working tree + a green
# test suite, then bump VERSION, commit the bump, tag vX.Y.Z, and push
# with --follow-tags. Use one of:
#
#   make release-patch     # bug-fix bump   (0.9.0 → 0.9.1)
#   make release-minor     # new-feature    (0.9.1 → 0.10.0)
#   make release-major     # breaking       (0.10.0 → 1.0.0)
#
# Picks up wherever main is — run from a clean main checkout. The
# Droplet's `make deploy` (run via SSH) is the actual ship step;
# `make release-*` only produces the tagged commit that `make deploy`
# will pull. Keeping the two concerns separate means a failed deploy
# doesn't leave you with a "version was bumped but never reached prod"
# inconsistency.
release-major: BUMP_KIND := major
release-minor: BUMP_KIND := minor
release-patch: BUMP_KIND := patch
release-major release-minor release-patch: _release_guard test _release_bump

# Internal: refuses to start a release if the working tree is dirty or
# the branch isn't `main`. Catches the common foot-gun of accidentally
# bumping from a feature branch.
_release_guard:
	@if [ -n "$$(git status --porcelain)" ]; then \
	  echo 'release: working tree is dirty; commit or stash first.'; exit 1; \
	fi
	@if [ "$$(git rev-parse --abbrev-ref HEAD)" != "main" ]; then \
	  echo 'release: must be on main (got $$(git rev-parse --abbrev-ref HEAD)).'; exit 1; \
	fi

# Internal: bump VERSION, commit, tag, push. Reads BUMP_KIND from the
# release-major / -minor / -patch parent target.
_release_bump:
	@new_version=$$(bundle exec ruby scripts/bump_version.rb $(BUMP_KIND)) && \
	  git add VERSION && \
	  git commit -m "chore: release v$$new_version" && \
	  git tag "v$$new_version" && \
	  git push --follow-tags origin main && \
	  echo "Released v$$new_version."

# ---- Container registry publishing (STUFF #33B) -----------------------------
# Build the production image on the operator's laptop, tag with the
# current VERSION + :latest, push to DigitalOcean Container Registry.
# The Droplet's `make deploy` pulls these tags rather than rebuilding
# locally — gives us tag-pinned rollback (set IMAGE_TAG=0.9.3 in
# /opt/app/.env and `docker compose up -d`).
#
# Cross-architecture: Apple Silicon Macs are arm64; the Droplet is
# amd64. `docker buildx build --platform linux/amd64` does the cross-
# compile in one command (slow first run while QEMU emulates the
# linker; subsequent builds reuse the buildx cache). Buildx ships with
# modern Docker Desktop / Colima by default; if you see
# "buildx not found", run `docker buildx create --use` once.
#
# Auth: `doctl registry login` (one-time on the laptop; uses your DO
# API token + sets up docker creds at ~/.docker/config.json). The
# Droplet's one-time setup is documented in DEPLOYMENT.md Phase 6.
#
# Tagging: every publish stamps TWO tags onto the same image —
# the exact semver (immutable, audit/rollback target) and :latest
# (mutable, points at most recent publish). The Droplet's compose
# file uses IMAGE_TAG (env-controlled, defaults to "latest"); set
# IMAGE_TAG=0.9.3 in /opt/app/.env to pin a rollback.

REGISTRY      ?= registry.digitalocean.com/tfr
IMAGE_NAME    ?= tech-feed-reader
IMAGE_VERSION = $(shell cat VERSION 2>/dev/null)

publish-image:
	@if [ -z "$(IMAGE_VERSION)" ] || [ "$(IMAGE_VERSION)" = "unknown" ]; then \
	  echo 'publish-image: VERSION missing or "unknown"; run `make release-*` first.'; exit 1; \
	fi
	@echo "Building $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_VERSION) for linux/amd64..."
	docker buildx build \
	  --platform linux/amd64 \
	  --build-arg APP_VERSION=$(IMAGE_VERSION) \
	  --tag $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_VERSION) \
	  --tag $(REGISTRY)/$(IMAGE_NAME):latest \
	  --push \
	  .
	@echo ''
	@echo "Published $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_VERSION)"
	@echo "Deploy with: ssh deploy@<droplet-ip> 'cd /opt/app && make deploy'"

# ---- Production deploy (run on the Droplet, not the laptop) -----------------
# One-liner deploy after `make publish-image` from the laptop. Pulls
# main (for Caddyfile / compose changes), pulls the new image from
# DOCR, force-recreates ONLY app + sidekiq containers (caddy + redis
# stay up the whole time — no TLS-cert blip, no Redis queue flush),
# then prints the last 50 log lines and exits.
#
# Behaviour modes:
#   make deploy             # default — prints recent logs ONCE and exits
#                           # (lets `make deploy-patch` from the laptop
#                           # return cleanly without hanging on the SSH
#                           # session's tail).
#   make deploy SHIP_TAIL=1 # follow logs continuously (-f). Useful when
#                           # SSH'd in interactively and you want to
#                           # watch the boot in real time; Ctrl-C out
#                           # when satisfied.
#
# Rollback: set IMAGE_TAG=0.9.3 in /opt/app/.env, then `make deploy`.
# IMAGE_TAG defaults to `latest` (always points at the most recent
# publish); pinning to a specific version is the rollback escape
# hatch from the registry pipeline.
#
# First-time setup (one-time per Droplet) is documented in
# DEPLOYMENT.md Phase 6: install doctl + `doctl registry login` so
# the deploy account can pull from registry.digitalocean.com/tfr.
deploy:
	git pull origin main
	docker compose pull app sidekiq
	docker compose up -d --force-recreate --no-deps app sidekiq
	@echo ''
	@if [ -n "$(SHIP_TAIL)" ]; then \
	  echo '--- tailing app logs (Ctrl-C to exit) ---'; \
	  docker compose logs -f --tail=50 app; \
	else \
	  echo '--- recent app logs ---'; \
	  docker compose logs --tail=50 --no-color app; \
	  echo ''; \
	  echo "Tail live with: docker compose logs -f --tail=30 app"; \
	fi

# ---- One-shot release + deploy (laptop) -------------------------------------
# Full ship cycle in one command. `make deploy-patch` does:
#   1. release-patch gate: clean tree, on main, full test suite green.
#   2. Bump VERSION, commit, tag, push to origin (--follow-tags).
#   3. publish-image: buildx cross-compile linux/amd64, push :ver +
#      :latest to DOCR.
#   4. SSH the Droplet (IP from `terraform output -raw droplet_ipv4`)
#      and trigger `make deploy` there.
# Bails on the first failure — tests red → no bump, no publish, no
# remote.
#
# DROPLET_USER + DROPLET_IP can be overridden on the command line:
#   make deploy-patch DROPLET_IP=1.2.3.4
# The terraform-output lookup runs in a subshell every invocation —
# adds ~150ms, but means a fresh `terraform apply` immediately
# propagates without operator-side coordination.

DROPLET_USER ?= deploy
DROPLET_IP   ?= $(shell cd terraform && terraform output -raw droplet_ipv4 2>/dev/null)

deploy-major: release-major publish-image _remote_deploy
deploy-minor: release-minor publish-image _remote_deploy
deploy-patch: release-patch publish-image _remote_deploy

_remote_deploy:
	@if [ -z "$(DROPLET_IP)" ]; then \
	  echo 'deploy: DROPLET_IP empty (terraform output -raw droplet_ipv4 failed).'; \
	  echo '         Set DROPLET_IP=... on the command line, or `cd terraform && terraform init`.'; \
	  exit 1; \
	fi
	@echo "Triggering remote deploy on $(DROPLET_USER)@$(DROPLET_IP)..."
	ssh $(DROPLET_USER)@$(DROPLET_IP) 'cd /opt/app && make deploy'
