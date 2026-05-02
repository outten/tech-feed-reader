.PHONY: run dev serve test install refresh-feeds refresh-feed scheduler

install:
	bundle install

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
