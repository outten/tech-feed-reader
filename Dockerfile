# syntax=docker/dockerfile:1
#
# Production container for the Sinatra app + Sidekiq worker. The same
# image runs both — docker-compose overrides the command for the
# sidekiq service. Multi-stage so the runtime layer doesn't carry
# build-essential / dev headers.
#
# Local dev still uses `make run` against host Ruby; this image is for
# the Droplet (see docker-compose.yml + DEPLOYMENT.md).

ARG RUBY_VERSION=3.4.1

# ---- VERSION (read by image labels + the runtime AppVersion module) -------
# Defaults to 'unknown' so a hand-rolled `docker build` from a working
# tree still produces a runnable image. Production builds pass
# --build-arg APP_VERSION=$(cat VERSION) so the OCI label + the in-app
# AppVersion::SEMVER pick up the real semver from the tagged commit.
ARG APP_VERSION=unknown

# ---- builder: install gems with build deps available -----------------------
FROM ruby:${RUBY_VERSION}-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      libsqlite3-dev \
      libyaml-dev \
      pkg-config \
      git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local deployment true \
 && bundle config set --local without 'development test' \
 && bundle install --jobs "$(nproc)" \
 && rm -rf vendor/bundle/ruby/*/cache

# ---- runtime: slim image with just the libs the gems need at runtime -------
FROM ruby:${RUBY_VERSION}-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      libsqlite3-0 \
      libyaml-0-2 \
      tzdata \
      curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 1000 app \
    && useradd  --uid 1000 --gid 1000 --create-home --shell /bin/bash app

WORKDIR /app
COPY --from=builder /app/vendor /app/vendor
COPY . .

# Bundler in the runtime stage uses BUNDLE_DEPLOYMENT + BUNDLE_PATH
# env (set below) to find the vendored gems — no need to copy the
# builder's .bundle/config.

# data/ holds the SQLite DB; tmp/ holds runtime scratch (logs, pids).
# Mount data/ as a volume in compose so it persists across container
# rebuilds. Both must be writable by the non-root user.
RUN mkdir -p /app/data /app/tmp && chown -R app:app /app

USER app

ENV RACK_ENV=production \
    BUNDLE_DEPLOYMENT=true \
    BUNDLE_PATH=vendor/bundle \
    BUNDLE_WITHOUT="development:test" \
    PORT=4567 \
    APP_VERSION=${APP_VERSION}

# OCI image labels — `docker inspect <image> | jq '.[0].Config.Labels'`
# is the supported way to ask "what version is this image?". The
# title + description are conventional; the version label matches
# AppVersion::SEMVER inside the running container.
LABEL org.opencontainers.image.title="Tech Feed Reader" \
      org.opencontainers.image.description="Personal RSS reader with ranking, AI triage, and per-account passkey auth." \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.source="https://github.com/outten/tech-feed-reader"

EXPOSE 4567

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://localhost:4567/health > /dev/null || exit 1

CMD ["bundle", "exec", "ruby", "app/main.rb"]
