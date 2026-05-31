require 'sinatra'
require 'sinatra/base'
require 'json'
require 'time'
require 'cgi'

# Loads .credentials + .env and aliases CLAUDE_API_KEY → ANTHROPIC_API_KEY
# so the Anthropic SDK picks it up. See app/credentials.rb.
require_relative 'credentials'

require_relative 'logger'
require_relative 'database'
require_relative 'feeds_store'
require_relative 'articles_store'
require_relative 'read_state_store'
require_relative 'tags_store'
require_relative 'tags_applier'
require_relative 'feed_fetcher'
require_relative 'health_registry'
require_relative 'scheduler'
require_relative 'summary_store'
require_relative 'summarizer/extractive'
require_relative 'summarizer/claude'
require_relative 'chat'
require_relative 'digests'
require_relative 'digest_store'
require_relative 'background_pool'
require_relative 'feed_feedback_store'
require_relative 'mute_rules_store'
require_relative 'support_messages_store'
require_relative 'account_export'
require_relative 'opml'
require_relative 'recommendation'
require_relative 'recommendation/for_you'
require_relative 'triage/claude'
require_relative 'triage_store'
require_relative 'feed_recommender/claude'
require_relative 'topic_clusters'
require_relative 'feed_catalog'
require_relative 'providers/itunes_lookup'
require_relative 'providers/youtube_channel_resolver'
require_relative 'providers/wikipedia'
require_relative 'auth'

# Phase A1 (consumer auth) — load .env in dev for SESSION_SECRET
# + WEBAUTHN_* config. Production reads from real env vars (host's
# launchd/systemd unit), no .env loaded. Test mode is also excluded
# now (Phase 5 / D-PG-2) so a developer's local DATABASE_URL doesn't
# hijack the suite — spec_helper.rb sets the needed test env vars
# explicitly and opts into PG via TEST_DATABASE_URL.
if ENV['RACK_ENV'].to_s == 'development' || ENV['RACK_ENV'].to_s.empty?
  begin
    require 'dotenv'
    Dotenv.load(File.expand_path('../../.env', __FILE__))
  rescue LoadError
    # dotenv isn't strictly required in dev either.
  end
end
require_relative 'sports_teams'
require_relative 'sports_catalog'
require_relative 'sports_leagues_store'
require_relative 'sports_teams_store'
require_relative 'sports_matches_store'
require_relative 'sports_standings_store'
require_relative 'sports_players_store'
require_relative 'sports_follows_store'
require_relative 'sports_entity_articles_store'
require_relative 'version'
require_relative 'tracing'
require_relative 'metrics'
require_relative 'request_log_middleware'
require_relative 'pageviews_store'
require_relative 'pruner'
require_relative 'metrics_middleware'
require_relative 'rate_limiter'
require_relative 'dev_stats'
require_relative 'llm_usage_store'
require_relative 'llm_guard'

# Sidekiq client config + the worker class. Loading the config only
# registers Sidekiq.configure_client/server blocks — no Redis
# connection happens until the first perform_async, so this is safe to
# require in test (specs stub perform_async).
require_relative 'sidekiq_config'
require_relative 'workers/feed_refresh_worker'
require_relative 'workers/sports_team_fetch_worker'
require 'sidekiq/api'

# Auto-migrate on boot for dev / production so `make run` always sees an
# up-to-date schema. Test env stays hermetic — specs that need tables
# call Database.migrate! themselves against the in-memory DB.
Database.migrate! unless ENV['RACK_ENV'] == 'test'

# Tech Feed Reader — single-user RSS / Atom aggregator.
#
# Architecture mirrors t-money-terminal: file-backed JSON stores under
# `data/`, cache-only render contract on the read paths, scheduled
# refresh as the only network event. See AGENTS.md for the full pattern.
#
# This file is the route skeleton — placeholder views render the empty
# states until the underlying stores + fetcher land. The intent is that
# `make install && make run` works on a fresh clone and gives you a
# navigable shell to build into.
class TechFeedReader < Sinatra::Base
  set :root, File.expand_path('../..', __FILE__)
  set :views, File.expand_path('../../views', __FILE__)
  set :public_folder, File.expand_path('../../public', __FILE__)
  set :port, 4567
  set :bind, '0.0.0.0' if ENV['RACK_ENV'] == 'production'

  # Phase A1 (consumer auth). Sinatra session cookie holds only the
  # signed-in user id (Integer) + a WebAuthn challenge (String,
  # transient). secure: only in prod since dev runs on plain HTTP;
  # SameSite=Lax is sufficient since the WebAuthn API blocks cross-
  # origin invocation anyway. SESSION_SECRET must be a long random
  # hex (`bundle exec ruby -rsecurerandom -e 'puts SecureRandom.hex(64)'`).
  enable :sessions
  set :session_secret, ENV.fetch('SESSION_SECRET') {
    if ENV['RACK_ENV'].to_s == 'test'
      'test-session-secret-' + ('0' * 96)
    else
      raise 'SESSION_SECRET not set. Generate one with `ruby -rsecurerandom -e \'puts SecureRandom.hex(64)\'` and add to .env.'
    end
  }
  set :sessions, key: 'tfr.session',
                 httponly: true,
                 secure: ENV['RACK_ENV'] == 'production',
                 same_site: :lax

  # Sinatra auto-enables Rack::Protection::HostAuthorization in
  # non-dev modes, rejecting requests whose Host header isn't in a
  # known list. Rack::Test defaults Host to "example.org", and
  # WEBAUTHN_ORIGIN's host needs an explicit allow. Configure via
  # :host_authorization (its own Sinatra setting, separate from
  # :protection — `set :protection, permitted_hosts:` is a no-op).
  permitted_hosts = ['localhost', '127.0.0.1', 'example.org']
  if (origin = ENV['WEBAUTHN_ORIGIN'])
    begin
      uri = URI(origin)
      permitted_hosts << uri.host if uri.host && !permitted_hosts.include?(uri.host)
    rescue URI::InvalidURIError
      # leave permitted_hosts as-is; fail-closed
    end
  end
  set :host_authorization, { permitted_hosts: permitted_hosts }

  # Protections we explicitly opt out of:
  #   :json_csrf       — SameSite cookie + custom Content-Type combo
  #                       means cross-origin forms can't post JSON
  #                       with our session anyway.
  #   :session_hijacking — STUFF #54. The default rack-protection
  #                       middleware fingerprints the session against
  #                       HTTP_USER_AGENT / HTTP_ACCEPT_ENCODING /
  #                       HTTP_ACCEPT_LANGUAGE and clears the session
  #                       if any change between requests. Browser
  #                       `fetch()` calls can normalise those headers
  #                       differently than the initial WebAuthn
  #                       request, silently destroying the session
  #                       for AJAX even though browser navigation
  #                       worked fine. The protection's value is low
  #                       (heuristic, defeated by easy spoofing) and
  #                       the cost was a totally broken AJAX-follow
  #                       experience.
  set :protection, except: %i[json_csrf session_hijacking]

  Auth.configure!

  # Surface the real exception in test runs so a 500 in rack-test prints
  # the underlying error class + backtrace instead of the bare "Internal
  # Server Error" page. Has no effect outside test env.
  configure :test do
    set :raise_errors, true
    set :dump_errors, false
    set :show_exceptions, false
  end

  # STUFF #64 — rack-mini-profiler. Dev-only badge in the top-left of
  # every HTML response with per-request timing + per-SQL-query
  # breakdown (auto-instruments the `pg` gem on load). Not bundled
  # into the production image (Gemfile group :development).
  configure :development do
    # rack-mini-profiler's pg-adapter patch is gated on `patch_rails?`
    # in the gem's auto-detect logic (lib/patches/sql_patches.rb) — so
    # in a non-Rails app the patch is silently skipped and SQL queries
    # never show up in the badge drill-down. Force-load the patch via
    # the documented `RACK_MINI_PROFILER_PATCH` env-var escape hatch.
    # Must be set BEFORE `require 'rack-mini-profiler'`; `pg` is
    # already loaded by `require_relative 'database'` above so the
    # monkey-patch finds its target.
    ENV['RACK_MINI_PROFILER_PATCH'] ||= 'pg'
    # rack-mini-profiler's lib/patches/net_patches.rb wraps Net::HTTP
    # via the same alias_method trick the pg patch uses; OTel's
    # net_http instrumentation prepends a wrapper that calls `super`,
    # so the two recurse infinitely the moment anything calls
    # Net::HTTP — most visibly the Anthropic SDK on /chat, /triage,
    # and /feeds/ai-recommend (SystemStackError, "internal.rb line 28").
    # Documented opt-out: setting this env var BEFORE require skips
    # the entire net_patches block. We don't need outbound-HTTP timing
    # from mini-profiler — OTel covers that path with no conflict.
    ENV['RACK_MINI_PROFILER_PATCH_NET_HTTP'] ||= 'false'
    require 'rack-mini-profiler'
    require 'stackprof' # enables ?pp=flamegraph
    Rack::MiniProfiler.config.enable_advanced_debugging_tools = true
    # Hide the call-stack column for anything under 250ms — the stack
    # only earns its keep on genuinely slow queries (joins, ranker
    # scans, FTS searches). Below the threshold queries still show
    # their duration; just no backtrace column.
    Rack::MiniProfiler.config.backtrace_threshold_ms = 250
    use Rack::MiniProfiler
  end

  # ---- Request logging ------------------------------------------------
  # Every HTTP request logs a single JSON line to STDOUT with
  # method / path / status / latency. Errors get a separate event
  # before being re-raised. See app/logger.rb for the format.

  # Cosmetics 7 — request logging is now done by RequestLogMiddleware
  # at the Rack layer (see `use` block above), which catches static
  # assets too. The old Sinatra before/after pair only saw dynamic
  # routes, which is why "I don't see page loads" looked broken even
  # though some loads were being logged.

  error do
    err = env['sinatra.error']
    AppLogger.error(
      'http_error',
      method:     request.request_method,
      path:       request.path_info,
      class:      err.class.name,
      message:    err.message,
      backtrace:  Array(err.backtrace).first(5)
    )
    raise err if settings.raise_errors?
    # Pre-launch — branded 500 page instead of Sinatra's default
    # grey trace. The structured AppLogger.error line above is what
    # the operator looks at; this is just the user-facing surface.
    @page_title  = 'Server error'
    @public_page = true
    halt 500, erb(:error_500)
  end

  # Pre-launch — branded 404 catch-all (any route the router doesn't
  # match). Keeps the tone consistent with the rest of the app rather
  # than the default Sinatra "Not Found" string.
  #
  # Important: if a route explicitly set a 404 body via `halt 404,
  # "..."`, leave it alone. The not_found handler fires AFTER halt,
  # so we'd otherwise stomp `halt 404, erb(:article_not_found)` and
  # similar per-route 404 surfaces. Detect a pre-existing body and
  # short-circuit.
  not_found do
    body_already_set = response.body && !response.body.empty? &&
                       !(response.body.is_a?(Array) && response.body.join.strip.empty?)
    next response.body if body_already_set

    if request.path_info.start_with?('/api/') ||
       request.env['HTTP_ACCEPT'].to_s.include?('application/json')
      content_type :json
      next JSON.generate(ok: false, error: 'not-found',
                         message: "No route matches #{request.path_info}.")
    end
    @page_title  = 'Not found'
    @public_page = true
    erb :not_found
  end

  # Phase A1 (consumer auth). Mix the Auth::Helpers methods into
  # Sinatra's request scope so `current_user` / `signed_in?` /
  # `require_signed_in!` / `sign_in!` / `sign_out!` are usable in
  # routes + views.
  helpers Auth::Helpers

  # Auth wall — every request that isn't public + isn't already
  # signed in bounces to /sign-in with a return_to. Runs after
  # Sinatra has matched a route but before the route block, so we
  # don't 404 on protected URLs while signed out (a 404 would leak
  # the URL exists).
  #
  # In RACK_ENV=test the wall is OFF by default — every existing
  # spec would otherwise need to sign-in before hitting any
  # protected route. Tests that explicitly want to exercise the wall
  # (spec/auth_spec.rb) flip `TechFeedReader.enforce_auth_wall = true`
  # in a before/after pair.
  set :enforce_auth_wall, ENV['RACK_ENV'] != 'test'
  before do
    if settings.enforce_auth_wall
      next if Auth.public_path?(request.path_info)
      unless signed_in?
        session[:return_to] = request.fullpath if request.get?
        redirect to('/sign-in')
      end
    else
      # Test/dev override: when the wall is off, every request implicitly
      # adopts user 1 (the seeded test user / single-user-mode owner).
      # Restores the pre-A2 "single user owns the app" behaviour so
      # existing specs continue to pass without a sign-in dance.
      # Skip auth endpoints themselves — sign-up / sign-in / /api/auth/*
      # need to see the unauthenticated visitor for their own ceremony.
      unless signed_in?
        # Skip auth endpoints (need to see the unauth visitor for the
        # ceremony) + the diagnostic endpoints (/health deliberately
        # tests an unreachable DB; running UsersStore.find here would
        # explode before the route returns its expected 503).
        next if request.path_info.start_with?('/sign-up', '/sign-in', '/sign-out', '/api/auth/')
        next if request.path_info == '/health' || request.path_info == '/metrics'
        user = UsersStore.find(1)
        sign_in!(user) if user
      end
    end

    # STUFF #49 — admin Basic Auth gate. /admin/* + /api/admin/*
    # need additional Basic Auth credentials beyond the existing
    # WebAuthn sign-in. ADMIN_USERNAME + ADMIN_PASSWORD live in
    # /opt/app/.env; missing/empty pair means everyone is denied
    # (fail-closed). 401 + WWW-Authenticate triggers the browser's
    # built-in credentials prompt.
    #
    # Logout flow (`POST /admin/logout` below) sets
    # `session[:admin_logged_out] = true` and redirects to `/`. While
    # that flag is set, this gate treats incoming admin requests as
    # un-authed even when the browser still has cached Basic Auth
    # credentials — re-entering the password (which clears the flag
    # in POST /admin/login) is required to get back in. The flag
    # itself lives in the signed-cookie session, so closing the
    # browser also clears it (no stuck-logged-out state).
    # /admin/login is the explicit "resume admin" escape hatch — it
    # MUST bypass the gate so a logged-out user can clear the flag.
    # The route handler itself doesn't depend on admin auth (it just
    # mutates a session flag); if the user lacks credentials, they'll
    # hit a fresh 401 on the next /admin request.
    if Auth.admin_path?(request.path_info) && request.path_info != '/admin/login'
      logged_out  = session[:admin_logged_out]
      basic_ok    = Auth.authorized_admin?(request.env)
      if logged_out
        # CRITICAL: don't send WWW-Authenticate when the user is
        # logged out via the session flag. The browser would pop a
        # credentials prompt, but the gate will reject ANY creds
        # while the flag is set — trapping the user in an infinite
        # 401-loop with no way out except deep browser-clearing.
        # Render the admin_denied page (logged-out variant) instead,
        # which has the "Resume admin" link to clear the flag.
        AppLogger.info('admin_logout_active',
                       user_id: signed_in? ? current_user_id : nil,
                       path:    request.path_info)
        @admin_logged_out = true
        halt 401, erb(:admin_denied)
      elsif !basic_ok
        # No flag set; standard prompt-for-credentials path.
        AppLogger.info('admin_basic_auth_denied',
                       user_id: signed_in? ? current_user_id : nil,
                       path:    request.path_info)
        response['WWW-Authenticate'] = 'Basic realm="Admin"'
        halt 401, erb(:admin_denied)
      end
    end
  end

  helpers do
    # Cache-bust query string for static assets — same pattern as t-money so
    # CSS/JS edits show up on next render without a hard reload.
    def asset_mtime(rel_path)
      full = File.join(settings.root, rel_path)
      File.exist?(full) ? File.mtime(full).to_i : Time.now.to_i
    end

    # STUFF.md #16 follow-up — extract the 11-char YouTube video ID
    # from an article's URL. Handles the canonical /watch?v=, /embed/,
    # /v/, /shorts/, and youtu.be/ patterns. Returns nil for anything
    # that doesn't look like YouTube. Strict on length (11 chars) so
    # we don't false-positive on YouTube URLs that don't carry a video.
    def youtube_video_id(article)
      url = article['url'].to_s
      return nil unless url.include?('youtube.com') || url.include?('youtu.be')
      match =
        url.match(%r{[?&]v=([\w-]{11})}) ||
        url.match(%r{youtube\.com/(?:embed|v|shorts)/([\w-]{11})}) ||
        url.match(%r{youtu\.be/([\w-]{11})})
      match && match[1]
    end

    # https://www.youtube.com/embed/<id> — the iframe-friendly URL.
    # No-cookie variant would be youtube-nocookie.com/embed/<id>; we
    # use the standard host since YouTube's privacy-enhanced mode
    # disables some features for autoplay/PiP.
    def youtube_embed_url(article)
      vid = youtube_video_id(article)
      vid && "https://www.youtube.com/embed/#{vid}"
    end

    # Standard YouTube CDN thumbnail URL. hqdefault is 480x360, served
    # for every public video, no API key needed. Used on /whats-on
    # "To watch today" cards so the section is visual.
    def youtube_thumbnail_url(article)
      vid = youtube_video_id(article)
      vid && "https://i.ytimg.com/vi/#{vid}/hqdefault.jpg"
    end

    # STUFF — format a YouTube video description for readable inline
    # display. The Atom feed delivers descriptions as plain text with
    # bare URLs, bare hashtags, and `\n` line breaks; rendered as HTML
    # the browser collapses all whitespace and leaves URLs unclickable
    # — exactly what the user reported (a "blob of letters and numbers").
    #
    # Output is escaped HTML with three classes of inline links wired:
    #   .yt-link      — auto-linked http/https URLs (new tab, noopener)
    #   .yt-timestamp — <button> carrying data-seconds; public/youtube-
    #                   watch.js seeks the embedded player on click
    #   .yt-hashtag   — link to YouTube's search-by-hashtag page
    #
    # Line breaks are preserved via `white-space: pre-line` on the
    # `.article-youtube-description` wrapper — no need to inject <br>.
    YT_DESC_PATTERN = %r{
      (?<url>https?://[^\s<>"]+)
      | (?<=^|\s)(?<hash>\#\w+)
      | (?<=^|[\s\(\[])(?<time>\d{1,2}:\d{2}(?::\d{2})?)\b
    }x.freeze

    def format_youtube_description_html(text)
      return '' if text.to_s.strip.empty?
      escaped = h(text.to_s)
      escaped.gsub(YT_DESC_PATTERN) do
        m = Regexp.last_match
        if m[:url]
          url = m[:url]
          trailing = +''
          while url.length > 1 && %w[. , ; ! ? )].include?(url[-1])
            trailing = url[-1] + trailing
            url = url[0..-2]
          end
          %(<a href="#{url}" rel="noopener noreferrer" target="_blank" class="yt-link">#{url}</a>#{trailing})
        elsif m[:time]
          stamp   = m[:time]
          seconds = stamp.split(':').map(&:to_i).reduce(0) { |acc, n| acc * 60 + n }
          %(<button type="button" class="yt-timestamp" data-seconds="#{seconds}">#{stamp}</button>)
        elsif m[:hash]
          tag = m[:hash][1..]
          %(<a href="https://www.youtube.com/results?search_query=%23#{tag}" rel="noopener noreferrer" target="_blank" class="yt-hashtag">##{tag}</a>)
        end
      end
    end

    # STUFF #26 — derive the human-facing YouTube channel URL from the
    # feed URL we subscribed to. Returns nil for any non-YouTube feed
    # URL so the caller can decide whether to render the "↗ Channel"
    # link at all. Used on /youtube to deep-link each channel card.
    def youtube_channel_url_from(feed_url)
      m = feed_url.to_s.match(%r{[?&]channel_id=(UC[\w-]+)})
      m && "https://www.youtube.com/channel/#{m[1]}"
    end

    # Used in feed-fetch UI; ISO8601 timestamps become "2 minutes ago".
    # Skim-mode summary line: prefer LLM, fall back to extractive,
    # else a content_text excerpt. Mirrors the precedence chain used
    # by Digests.pick_summary so the two views read consistently.
    SKIM_EXCERPT_FALLBACK_CHARS = 240
    def skim_summary_for(article, summary_row)
      llm = summary_row && summary_row['llm'].to_s.strip
      return llm unless llm.nil? || llm.empty?
      extractive = summary_row && summary_row['extractive'].to_s.strip
      return extractive unless extractive.nil? || extractive.empty?
      excerpt = article['content_text'].to_s.strip
      return '' if excerpt.empty?
      excerpt.length > SKIM_EXCERPT_FALLBACK_CHARS ? "#{excerpt[0, SKIM_EXCERPT_FALLBACK_CHARS].rstrip}…" : excerpt
    end

    # JSON body parser for routes that take application/json. Returns
    # nil on malformed input so the caller can 400 cleanly without a
    # raised exception leaking out of the route block.
    def parse_json_body
      raw = request.body.read
      request.body.rewind
      return nil if raw.to_s.strip.empty?
      JSON.parse(raw)
    rescue JSON::ParserError
      nil
    end

    # True when the client signals it wants JSON (the AJAX path used
    # by public/sports-follow.js + similar). HTML form submits set
    # Accept: text/html,…, so they take the 302 fallback.
    def wants_json?
      request.env['HTTP_ACCEPT'].to_s.include?('application/json')
    end

    # Shared shape for the four sports follow/unfollow routes so the
    # JS handler in public/sports-follow.js can toggle button state
    # without round-tripping HTML. The `followed` field is the
    # authoritative new state — JS doesn't have to guess from the
    # request kind.
    def sports_follow_json(slug:, kind:, followed:)
      content_type :json
      { ok: true, slug: slug, kind: kind, followed: followed }.to_json
    end

    def relative_time(iso)
      return '—' if iso.nil? || iso.to_s.empty?
      t = iso.is_a?(Time) ? iso : (Time.parse(iso.to_s) rescue nil)
      return '—' unless t
      diff = Time.now - t
      case diff
      when 0..60          then 'just now'
      when 61..3600       then "#{(diff / 60).round}m ago"
      when 3601..86_400   then "#{(diff / 3600).round}h ago"
      else                     "#{(diff / 86_400).round}d ago"
      end
    end

    # Lookup helper for views — turns a feed_id into a feeds row using
    # the @feeds_by_id hash the route handler builds. Returns nil if the
    # feed has been deleted (orphaned articles shouldn't happen thanks
    # to ON DELETE CASCADE, but stay safe).
    def feed_for(article)
      (@feeds_by_id ||= {})[article['feed_id']]
    end

    # STUFF.md #17 / #14 follow-up — gathers the four What's On Today
    # buckets (matches / reads / listens / watch) used by both the
    # returning-user branch of GET / and any legacy callers. Mutates
    # the route-scoped instance variables in place so the view template
    # can read them directly. Keeps the data source single-sourced
    # rather than copy-pasted between the / and (formerly) /whats-on
    # routes.
    def load_whats_on_today!
      today        = Date.today
      start_of_day = Time.new(today.year, today.month, today.day, 0, 0, 0).utc

      @today_matches = SportsMatchesStore.upcoming_for_followed_teams(current_user_id, days_forward: 1)

      scored = Recommendation::ForYou.score_window(current_user_id, state: :all, limit: 200, offset: 0)
      todays = scored.select { |a| a['published_at'].to_s >= start_of_day.iso8601 }

      @feeds_by_id ||= FeedsStore.for_user(current_user_id).each_with_object({}) { |f, h| h[f['id']] = f }

      # Phase 2 follow-up (2026-05-12) — "To watch today" partitions
      # by whether the article has a YouTube video URL, NOT by feed
      # topic. So a Premier League highlight clip from the new
      # :youtube_sports channels shows up alongside BBC Earth, and a
      # tech YouTube channel would too if you ever subscribed to one.
      all_listens = todays.select { |a| a['audio_url'].to_s.size.positive? }
      @today_listening = all_listens.first(10)
      videos_today, non_video = todays.reject { |a| a['audio_url'].to_s.size.positive? }
                                      .partition { |a| youtube_video_id(a) }
      @today_watching = videos_today.first(10)
      @today_reading  = non_video.first(10)

      # Phase 3 follow-up (2026-05-12) — surface bus mode on the home.
      # Bus mode (header 🚌 icon) lists podcast episodes ≤15 minutes
      # so the user can pick something for the commute. The icon is
      # easy to miss; this exposes the count alongside today's listens.
      bus_cutoff_seconds = BUS_DEFAULT_MAX_MINUTES * 60
      @bus_count_today = all_listens.count do |a|
        dur = a['audio_duration_seconds'].to_i
        dur.positive? && dur <= bus_cutoff_seconds
      end

      @summaries_by_article_id = SummaryStore.find_for_ids(
        (@today_reading + @today_listening + @today_watching).map { |a| a['id'] }
      )
      @teams_by_id   = build_teams_by_id_for_matches(@today_matches)
      @leagues_by_id = build_leagues_by_id_for_matches(@today_matches)
      @nothing_today = @today_matches.empty? && @today_reading.empty? &&
                       @today_listening.empty? && @today_watching.empty?
    end

    # Estimated reading time for an article in whole minutes, based
    # on the cleaned content_text word count at ~200 words/min. Returns
    # nil for articles whose primary mode is audio (podcasts) or video
    # (YouTube) since "reading time" is meaningless there — the row
    # already shows duration / a play affordance. Caps at 60 min and
    # returns nil under 1 min (sub-minute pills add noise, not value).
    def reading_time_minutes(article)
      return nil if article['audio_url'].to_s.size.positive?
      return nil if youtube_video_id(article)
      text = article['content_text'].to_s
      return nil if text.empty?
      words = text.split(/\s+/).length
      return nil if words < 100
      minutes = (words / 200.0).ceil
      [minutes, 60].min
    end

    # STUFF.md follow-up — feed with the most articles published in
    # the last 24h, returned as a row from `feeds` (or nil if no
    # articles published in that window). Powers the "freshest source
    # today" line on /articles. Single small query — bounded by an
    # index on articles.published_at.
    def articles_most_active_feed_24h
      since = (Time.now.utc - 24 * 60 * 60).iso8601
      row = Database.connection.execute(<<~SQL, [since]).first
        SELECT f.id, f.title, f.url, COUNT(*) AS c, MAX(a.published_at) AS latest_at
        FROM articles a
        JOIN feeds f ON f.id = a.feed_id
        WHERE a.published_at >= ?
        GROUP BY f.id
        ORDER BY c DESC, latest_at DESC
        LIMIT 1
      SQL
      row && row['c'].to_i.positive? ? row : nil
    end

    # STUFF.md follow-up — day-group label for the article-list
    # dividers. Buckets relative to "today" in the server's local
    # timezone since most users will be in the same TZ as the server.
    # Returns one of: 'Today', 'Yesterday', 'Earlier this week',
    # 'Earlier this month', 'Older'.
    def day_group_label_for(published_at)
      return 'Undated' if published_at.to_s.empty?
      published = (Time.parse(published_at.to_s).getlocal.to_date rescue nil)
      return 'Undated' unless published

      today = Date.today
      days  = (today - published).to_i
      case days
      when 0    then 'Today'
      when 1    then 'Yesterday'
      when 2..6 then 'Earlier this week'
      when 7..30 then 'Earlier this month'
      else 'Older'
      end
    end

    # Phase S10 — single source of truth for the top-level topic
    # filter validator. Accepts any FeedCatalog::TOPICS key plus
    # 'general' (for arbitrary URL-added feeds); nil for unrecognised
    # values so callers can default cleanly.
    def sanitize_topic_filter(raw)
      valid = FeedCatalog::TOPICS.keys.map(&:to_s) + %w[general]
      valid.include?(raw.to_s) ? raw.to_s : nil
    end

    # Triage helpers — used by the /triage routes to share rendering
    # paths between live POST results and historical GET /triage/:id
    # rows. The struct shape matches Triage::Claude::Result so the
    # view template doesn't have to branch on data source.
    def triage_struct_from_row(row)
      Triage::Claude::Result.new(
        status:        row['status'].to_sym,
        must_read:     Array(row['must_read']),
        optional:      Array(row['optional']),
        skip:          Array(row['skip']),
        model:         row['model'],
        latency_ms:    row['latency_ms'],
        input_tokens:  row['input_tokens'],
        output_tokens: row['output_tokens'],
        unread_count:  row['unread_count'].to_i,
        error:         row['error']
      )
    end

    # STUFF #52 — when a user follows a team that exists in the
    # SportsCatalog but hasn't been seeded into the DB yet, materialise
    # it (and its parent league) on demand. Idempotent thanks to the
    # underlying upserts. Returns the team row from sports_teams, or
    # nil if the slug isn't in the catalog at all.
    def ensure_catalog_team_in_db(team_slug)
      catalog_team = SportsCatalog.find_team(team_slug)
      return nil unless catalog_team

      catalog_league = SportsCatalog.find_league(catalog_team[:sport_slug], catalog_team[:league_slug])
      return nil unless catalog_league

      league = SportsLeaguesStore.upsert(
        slug:            catalog_league[:slug],
        name:            catalog_league[:name],
        sport:           catalog_league[:sport],
        source_provider: catalog_league[:source_provider] || 'catalog',
        external_id:     catalog_league[:external_id]     || catalog_league[:slug],
        country:         catalog_league[:country]
      )

      # STUFF #69 — the ESPN standings sync may have already created
      # a row for this team under the auto-slug pattern
      # `<league>-team-<external_id>` (e.g. `nba-team-13` for the
      # Lakers). `SportsTeamsStore.upsert` finds existing rows by
      # `(source_provider, external_id)` and updates their columns,
      # but never touches the slug — so without an explicit rename
      # the auto-slug persists. Result: a follow stored with the
      # catalog slug (`lakers`) doesn't match any DB row at lookup
      # time, and the team never surfaces on /sports.
      #
      # Detect the mismatched row, rename its slug to the catalog
      # canonical, THEN run upsert (which now hits the renamed row
      # via the same external_id and refreshes name/image/etc.).
      provider    = catalog_team[:source_provider] || 'catalog'
      external_id = catalog_team[:external_id]     || catalog_team[:slug]
      existing    = SportsTeamsStore.find_by_external(provider, external_id, league_id: league['id'])
      if existing && existing['slug'] != catalog_team[:slug]
        SportsTeamsStore.rename_slug!(existing['id'], catalog_team[:slug])
      end

      SportsTeamsStore.upsert(
        league_id:       league['id'],
        slug:            catalog_team[:slug],
        name:            catalog_team[:name],
        short_name:      catalog_team[:short_name],
        location:        catalog_team[:location],
        image_url:       catalog_team[:image_url],
        source_provider: provider,
        external_id:     external_id
      )
    end

    # STUFF #70 — analog for league-shaped catalog entries (mostly
    # tournaments). When a user follows a tournament that doesn't yet
    # have a sports_leagues row, materialize it on demand so the
    # follow target exists. Same idea as ensure_catalog_team_in_db
    # but no league_id parent to resolve — leagues are the top level.
    def ensure_catalog_league_in_db(league_slug)
      catalog_league = SportsCatalog.all_leagues.find { |lg| lg[:slug] == league_slug.to_s }
      return nil unless catalog_league

      row = SportsLeaguesStore.upsert(
        slug:            catalog_league[:slug],
        name:            catalog_league[:name],
        sport:           catalog_league[:sport],
        source_provider: catalog_league[:source_provider] || 'catalog',
        external_id:     catalog_league[:external_id]     || catalog_league[:slug],
        country:         catalog_league[:country]
      )
      # STUFF #73 — stamp the Wikipedia title from the catalog so the
      # summary provider can pick it up. Only writes when the catalog
      # has a mapping AND the row doesn't already carry one (lets a
      # human override stick).
      wiki = SportsCatalog.wikipedia_title_for(league_slug)
      if wiki && row['wikipedia_title'].to_s.empty?
        SportsLeaguesStore.set_wikipedia_title!(row['id'], wiki)
        row = SportsLeaguesStore.find(row['id'])
      end
      row
    end

    # STUFF #52.1 — catalog players (notable-player chips on team
    # cards) live in app/sports_catalog.rb as plain strings under
    # `team[:players]`. Clicking a chip needs to land on the player
    # detail page; that requires a sports_players row. This helper
    # upserts on demand, mirroring ensure_catalog_team_in_db above.
    #
    # The player's globally-unique slug is `"#{team_slug}-#{name_slug}"`
    # so two teams that happen to share a player name (rare in the
    # curated catalog) don't collide. The source_provider/external_id
    # keys carry the same composite so re-upserts are idempotent.
    def ensure_catalog_player_in_db(team_slug, player_name)
      catalog_team = SportsCatalog.find_team(team_slug)
      return nil unless catalog_team
      return nil unless (catalog_team[:players] || []).include?(player_name)

      catalog_league = SportsCatalog.find_league(catalog_team[:sport_slug], catalog_team[:league_slug])
      return nil unless catalog_league

      slug = catalog_player_slug(team_slug, player_name)
      SportsPlayersStore.upsert(
        sport:           catalog_league[:sport],
        slug:            slug,
        full_name:       player_name,
        source_provider: 'catalog',
        external_id:     slug
      )
    end

    # Resolve a catalog player from its composite slug. Walks the
    # catalog looking for a team whose slug is a prefix and a player
    # whose name slug matches the remainder. Returns the upserted
    # sports_players row, or nil if no catalog match.
    def ensure_catalog_player_by_slug(slug)
      SportsCatalog.all_teams.each do |team|
        prefix = "#{team[:slug]}-"
        next unless slug.to_s.start_with?(prefix)
        suffix = slug[prefix.length..]
        (team[:players] || []).each do |player_name|
          return ensure_catalog_player_in_db(team[:slug], player_name) if slugify(player_name) == suffix
        end
      end
      nil
    end

    def catalog_player_slug(team_slug, player_name)
      "#{team_slug}-#{slugify(player_name)}"
    end

    def slugify(s)
      s.to_s.unicode_normalize(:nfkd).gsub(/[^\x00-\x7F]/, '').downcase
       .gsub(/[^a-z0-9]+/, '-').gsub(/^-+|-+$/, '')
    end

    # Phase S9 helpers — build lookup tables for a list of match
    # rows so the calendar view doesn't N+1 across 30+ rows.
    def build_teams_by_id_for_matches(matches)
      ids = matches.flat_map { |m| [m['home_team_id'], m['away_team_id']] }.compact.uniq
      ids.each_with_object({}) { |id, h| h[id] = SportsTeamsStore.find(id) }
    end

    def build_leagues_by_id_for_matches(matches)
      ids = matches.map { |m| m['league_id'] }.compact.uniq
      ids.each_with_object({}) { |id, h| h[id] = SportsLeaguesStore.find(id) }
    end

    # Group matches by local-day key (YYYY-MM-DD in the user's
    # locale, which we approximate as Process-local Time.parse →
    # Time#strftime). Returns an array of [day_key, [matches]]
    # pairs in chronological order — convenient for the view's
    # `<% @grouped.each do |day, matches| %>` loop.
    def group_by_local_day(matches)
      grouped = matches.group_by do |m|
        t = (Time.parse(m['scheduled_at'].to_s) rescue nil)
        t ? t.localtime.strftime('%Y-%m-%d') : 'unknown'
      end
      grouped.sort_by { |k, _| k }
    end

    # Per-sport default match duration in hours. Used as the iCal
    # DTEND offset since match rows don't carry a duration.
    SPORT_DURATION_HOURS = {
      'football'   => 3.5,
      'basketball' => 2.5,
      'soccer'     => 2.0,
      'rugby'      => 2.0
    }.freeze
    SPORT_DURATION_DEFAULT = 2.5

    def duration_hours_for(league)
      SPORT_DURATION_HOURS[(league && league['sport']).to_s] || SPORT_DURATION_DEFAULT
    end

    # Build the .ics payload for the calendar export. RFC 5545:
    # CRLF line endings, escaped commas / semicolons / newlines
    # in TEXT properties, DATE-TIME in UTC with trailing 'Z'.
    def build_ical(matches, teams_by_id, leagues_by_id, now: Time.now.utc)
      lines = []
      lines << 'BEGIN:VCALENDAR'
      lines << 'VERSION:2.0'
      lines << 'PRODID:-//tech-feed-reader//sports-calendar//EN'
      lines << 'CALSCALE:GREGORIAN'
      lines << 'METHOD:PUBLISH'
      lines << ical_text('X-WR-CALNAME', 'Tech Feed Reader — Sports')
      lines << ical_text('X-WR-CALDESC', 'Upcoming fixtures across every followed team.')

      dtstamp = now.strftime('%Y%m%dT%H%M%SZ')
      matches.each do |m|
        league = leagues_by_id[m['league_id']]
        home   = teams_by_id[m['home_team_id']]
        away   = teams_by_id[m['away_team_id']]
        start_t = Time.parse(m['scheduled_at'].to_s).utc rescue nil
        next unless start_t
        end_t   = start_t + (duration_hours_for(league) * 3600).to_i

        home_label = home ? (home['name'] || home['short_name']) : 'TBD'
        away_label = away ? (away['name'] || away['short_name']) : 'TBD'
        league_lbl = league ? league['name'] : 'Sports'
        summary    = "#{away_label} @ #{home_label}"
        description_parts = [
          league_lbl,
          (m['venue'].to_s.empty? ? nil : "Venue: #{m['venue']}")
        ].compact

        lines << 'BEGIN:VEVENT'
        lines << "UID:tfr-sports-match-#{m['id']}@tech-feed-reader"
        lines << "DTSTAMP:#{dtstamp}"
        lines << "DTSTART:#{start_t.strftime('%Y%m%dT%H%M%SZ')}"
        lines << "DTEND:#{end_t.strftime('%Y%m%dT%H%M%SZ')}"
        lines << ical_text('SUMMARY', summary)
        lines << ical_text('LOCATION', m['venue'].to_s) unless m['venue'].to_s.empty?
        lines << ical_text('DESCRIPTION', description_parts.join("\n"))
        lines << "STATUS:#{m['status'] == 'live' ? 'CONFIRMED' : 'TENTATIVE'}"
        lines << 'END:VEVENT'
      end

      lines << 'END:VCALENDAR'
      lines.join("\r\n") + "\r\n"
    end

    # RFC 5545 escapes for TEXT-typed properties. Backslash first
    # so subsequent escapes don't get re-escaped.
    def ical_text(key, value)
      escaped = value.to_s
                     .gsub('\\', '\\\\')
                     .gsub(',',  '\\,')
                     .gsub(';',  '\\;')
                     .gsub("\n", '\\n')
                     .gsub("\r", '')
      "#{key}:#{escaped}"
    end

    # Leagues the user implicitly follows because they follow ≥1
    # team in that league. Drives the "By league:" TOC row on
    # /sports and the future calendar/iCal scope (S9).
    def leagues_for_followed_teams
      slugs = SportsFollowsStore.for_kind(current_user_id, 'team').map { |f| f['value'] }
      return [] if slugs.empty?
      league_ids = slugs.filter_map { |s| (t = SportsTeamsStore.find_by_slug(s)) && t['league_id'] }.uniq
      league_ids.filter_map { |lid| SportsLeaguesStore.find(lid) }
    end

    # 1st / 2nd / 3rd / 4th. Used in the league-position subtitle
    # on the team detail page.
    def position_suffix(n)
      return ''  if n.nil? || n <= 0
      return 'th' if [11, 12, 13].include?(n % 100)
      case n % 10
      when 1 then 'st'
      when 2 then 'nd'
      when 3 then 'rd'
      else        'th'
      end
    end

    # STUFF.md #9 — last final per followed team for the score
    # tiles on /sports. Maps a SportsTeams Ruby module slug to the
    # corresponding sports_matches row (or nil if no final synced
    # yet). Skips teams that don't have a structured-data row
    # (e.g. tennis, where the user follows the sport not a team).
    def build_last_finals(teams)
      teams.each_with_object({}) do |team, acc|
        m = lookup_last_final_for_team(team)
        acc[team[:slug]] = m if m
      end
    end

    # STUFF #68 — present a DB-side sports_teams row as a Hash that
    # mimics the curated `SportsTeams::TEAMS` entries (symbol keys,
    # the four fields the /sports view actually reads). Lets us merge
    # both team sources into a single `@teams_with_subs` list without
    # branching the view. Same idea as the DB-fallback path on
    # /sports/team/:slug from STUFF #67.
    def db_team_as_curated(row)
      {
        slug:       row['slug'],
        name:       row['name'],
        short_name: row['short_name'] || row['name'],
        image_url:  row['image_url'],
        # The view shows :emoji only when image_url is empty — DB
        # teams nearly always carry a logo from the ESPN sync, but
        # fall back to a generic stadium glyph just in case.
        emoji:      '🏟',
        sport:      nil,
        feed_urls:  []
      }
    end

    # Resolve a SportsTeams Ruby module entry to its
    # sports_teams.id and pull the most recent final. The Ruby
    # module's slug is the bridging key; if the structured layer
    # doesn't have a matching row (catalog mismatch / tennis),
    # returns nil cleanly.
    def lookup_last_final_for_team(team)
      return nil unless team
      row = SportsTeamsStore.find_by_slug(team[:slug])
      return nil unless row
      SportsMatchesStore.recent_finals_for_team(row['id'], limit: 1).first
    end

    # Helper for the score-tile view: given a match row + the
    # focal team's id (the team the tile belongs to), returns a
    # hash with the focal/opponent split + W/L tag. Drives the
    # one-place-of-truth rendering for /sports tiles + the per-
    # team detail page's "Last game" section.
    def score_tile_view(match, focal_team_id)
      home_id   = match['home_team_id']
      away_id   = match['away_team_id']
      home_score = match['home_score'].to_i
      away_score = match['away_score'].to_i
      home_team  = home_id ? SportsTeamsStore.find(home_id) : nil
      away_team  = away_id ? SportsTeamsStore.find(away_id) : nil

      focal_is_home = (home_id == focal_team_id)
      focal_team    = focal_is_home ? home_team : away_team
      opponent_team = focal_is_home ? away_team : home_team
      focal_score   = focal_is_home ? home_score : away_score
      opp_score     = focal_is_home ? away_score : home_score

      result =
        if focal_score > opp_score then 'W'
        elsif focal_score < opp_score then 'L'
        else 'D'
        end

      {
        focal:        focal_team,
        opponent:     opponent_team,
        focal_score:  focal_score,
        opp_score:    opp_score,
        result:       result,
        home_away:    focal_is_home ? 'home' : 'away',
        scheduled_at: match['scheduled_at'],
        venue:        match['venue']
      }
    end

    def preload_articles_by_uid(result)
      uids = (result.must_read.to_a + result.optional.to_a + result.skip.to_a)
               .map { |e| e['uid'] }.compact
      uids.each_with_object({}) do |uid, h|
        a = ArticlesStore.find_by_uid(uid)
        h[uid] = a if a
      end
    end

    # HTML-escape helper for user-controlled strings reflected back into
    # the page (e.g. the search query). Sinatra-default ERB does not
    # auto-escape `<%= %>` output, so dynamic data reflected verbatim
    # would be an XSS vector.
    def h(text)
      Rack::Utils.escape_html(text.to_s)
    end

    # ---- /health probes -----------------------------------------------
    # Each `check_*` method returns a hash shaped { status: 'ok'|'down'|
    # 'disabled', ... } so the /health JSON is uniform across deps. They
    # rescue any underlying error and surface the message; nothing here
    # should be able to take the route down.

    def check_db
      Database.connection.execute('SELECT 1').first
      { status: 'ok' }
    rescue => e
      { status: 'down', error: e.message }
    end

    def check_redis
      Sidekiq.redis { |r| r.ping }
      { status: 'ok' }
    rescue => e
      { status: 'down', error: e.message }
    end

    def check_sidekiq
      processes = Sidekiq::ProcessSet.new
      { status: processes.size.positive? ? 'ok' : 'no_workers',
        workers: processes.size }
    rescue => e
      { status: 'down', error: e.message }
    end

    # Probe Sidekiq for queue depth + worker count. Returns
    # `{ ok: false, error: 'connection refused' }` when Redis is down so
    # /admin doesn't 500 in environments without a worker process.
    def sidekiq_stats
      stats = Sidekiq::Stats.new
      processes = Sidekiq::ProcessSet.new
      {
        ok:        true,
        enqueued:  stats.enqueued,
        scheduled: stats.scheduled_size,
        retries:   stats.retry_size,
        dead:      stats.dead_size,
        processed: stats.processed,
        failed:    stats.failed,
        workers:   processes.size
      }
    rescue => e
      { ok: false, error: e.message }
    end

    # Render the per-row feeds-table partial. Used both by views/feeds.erb
    # (server-side) and the /api/feeds endpoints (returned as `row_html`)
    # so JS-inserted rows match server-rendered ones.
    def render_feed_row(feed)
      weight = FeedFeedbackStore.weight_for(current_user_id, feed['id'])
      erb :_feed_row, locals: { feed: feed, weight: weight }, layout: false
    end

    # Format a duration in seconds as "12:34" or "1:23:45". Returns
    # nil for nil / zero so the view can decide whether to render the
    # span at all.
    def fmt_duration(seconds)
      s = seconds.to_i
      return nil if s <= 0
      h = s / 3600
      m = (s % 3600) / 60
      sec = s % 60
      if h > 0
        format('%d:%02d:%02d', h, m, sec)
      else
        format('%d:%02d', m, sec)
      end
    end

    # Format a byte count as 1.5 MB / 240 KB / 332 B for the admin
    # dashboard. Inline to avoid pulling in ActiveSupport for one call
    # site.
    def number_to_human_size(bytes)
      bytes = bytes.to_i
      return '0 B' if bytes.zero?
      units = %w[B KB MB GB TB]
      i = (Math.log(bytes) / Math.log(1024)).to_i
      i = units.length - 1 if i >= units.length
      value = bytes.to_f / (1024**i)
      format(i.zero? ? '%d %s' : '%.1f %s', value, units[i])
    end

    # Build the /articles query string from the current filter state, with
    # per-call overrides. Captures state / kind / view / sort / feed_id /
    # tag / page so chip toggles and the pager don't have to hand-stitch
    # the query string (and silently drop params they forgot about — that
    # was the bug behind "turning on Skim reverts to page 1," because the
    # skim toggle's hand-built URL didn't carry `page`).
    #
    # Defaults (state=:all, view=:default, sort=:chronological, kind=:all,
    # page=1) are dropped from the URL — the bare `/articles` route
    # already lands you in those, so emitting them only adds noise.
    #
    # Pass nil in `overrides` to clear an inherited param. Example:
    #
    #   filter_url(view: :skim)            # → preserves everything, adds skim
    #   filter_url(view: nil)              # → preserves everything, removes skim
    #   filter_url(state: :unread, page: nil) # changing state resets pagination
    def filter_url(overrides = {})
      current = {
        state:   @state_filter == :all          ? nil : @state_filter,
        kind:    @kind_filter == :podcast       ? :podcast    : nil,
        view:    @view_filter == :skim          ? :skim       : nil,
        sort:    @sort_filter == :relevance     ? :relevance  : nil,
        topic:   @topic_filter,
        feed_id: @feed_filter && @feed_filter['id'],
        tag:     @tag_filter  && @tag_filter['id'],
        page:    (@page && @page > 1)           ? @page       : nil
      }

      merged = current.merge(overrides)
      # Iterate in a fixed canonical order so URLs are stable regardless
      # of which override the caller passed first.
      pairs = %i[state kind view sort topic feed_id tag page]
                .map { |k| [k, merged[k]] }
                .reject { |_, v| v.nil? || v.to_s.empty? }
      pairs.empty? ? '?' : "?#{pairs.map { |k, v| "#{k}=#{v}" }.join('&')}"
    end
  end

  # ---- Routes ---------------------------------------------------------

  # Liveness + readiness probe. Designed for `curl` and uptime monitors:
  # always returns JSON, no auth, no session, no template rendering.
  #
  # Status codes:
  #   200 — every critical dependency is up. SQLite is the only true
  #         critical dep; Redis being down only degrades async refresh.
  #   503 — SQLite is unreachable. The web app can't serve articles
  #         without it, so this is the one we want load balancers to
  #         pull traffic away from.
  #
  # The `current_time` field (TOD) is the server clock at the moment
  # this handler runs, useful for spotting clock-skew issues against
  # external systems.
  get '/health' do
    content_type :json

    db_status = check_db
    redis_check = check_redis

    overall =
      if db_status[:status] != 'ok'
        'fail'
      elsif redis_check[:status] != 'ok'
        'degraded'
      else
        'ok'
      end

    status(503) if overall == 'fail'

    {
      status:         overall,
      version:        AppVersion::SEMVER,
      git_sha:        AppVersion::GIT_SHA,
      started_at:     AppVersion::STARTED_AT.iso8601,
      uptime_seconds: AppVersion.uptime_seconds,
      current_time:   Time.now.utc.iso8601,
      checks: {
        db:      db_status,
        redis:   redis_check,
        sidekiq: check_sidekiq
      }
    }.to_json
  end

  # Prometheus scrape endpoint. Refreshes the gauges that aren't
  # event-driven (counts, queue depth, uptime) just before exporting,
  # so a scrape always reflects the latest snapshot.
  #
  # No auth — this is a single-user app and the metrics are
  # operationally useful from the host's local network. If you ever
  # expose this beyond localhost, put a reverse proxy in front and
  # restrict /metrics there.
  get '/metrics' do
    Metrics::FEEDS_SUBSCRIBED.set(FeedsStore.count)
    Metrics::ARTICLES_TOTAL.set(ArticlesStore.count)
    Metrics::UPTIME.set(AppVersion.uptime_seconds)

    # Sidekiq stats hit Redis; protect the route from a Redis outage so
    # /metrics still emits the SQLite-derived gauges.
    begin
      Metrics::SIDEKIQ_QUEUE_DEPTH.set(Sidekiq::Stats.new.enqueued)
      Metrics::SIDEKIQ_WORKERS.set(Sidekiq::ProcessSet.new.size)
    rescue StandardError
      # Leave gauges at last known value (or 0 on first call).
    end

    content_type 'text/plain; version=0.0.4; charset=utf-8'
    Prometheus::Client::Formats::Text.marshal(Metrics::REGISTRY)
  end

  # STUFF.md #13 / #14 / #17 — / is the canonical home.
  # Three modes:
  #   • Anonymous (not signed in) → marketing pitch + feature cards.
  #   • Signed-in but no feed subscriptions (brand-new signup) → 302
  #     to /welcome so onboarding picks topic chips for them. Without
  #     this branch a fresh signup lands on the marketing pitch and
  #     re-prompts for sign-up, which is awkward.
  #   • Returning user → What's On Today (matches / reads / listens /
  #     watch) personalized by follows + For You ranker.
  # The Dashboard (operational stats + Activity chart) moved to
  # /admin/dashboard since it's an ops view, not a daily-use surface.
  get '/' do
    if signed_in? && FeedsStore.count_for_user(current_user_id).zero?
      redirect to('/welcome')
    end

    @page_title  = 'Feeder'
    @public_page = true
    @returning_user = signed_in? &&
                      ArticlesStore.count.positive? &&
                      ReadStateStore.any_activity?(current_user_id)
    if @returning_user
      load_whats_on_today!
      @stats = {
        unread:     ReadStateStore.unread_count(current_user_id),
        bookmarks:  ReadStateStore.bookmarked_count(current_user_id),
        articles:   ArticlesStore.count_for_user(current_user_id)
      }
      @latest_triage = TriageStore.latest(current_user_id)
    end
    erb :home
  end

  get '/about' do
    @page_title  = 'About'
    @public_page = true
    erb :about
  end

  # STUFF #62 — public legal pages. Both reachable without sign-in
  # (Auth::PUBLIC_PATHS); footer links + crawlable for SEO so a
  # privacy-cautious user can read them before signing up.
  get '/privacy' do
    @page_title  = 'Privacy'
    @public_page = true
    erb :privacy
  end

  get '/terms' do
    @page_title  = 'Terms of Use'
    @public_page = true
    erb :terms
  end

  # STUFF #62 — public contact form. No auth wall (added to
  # Auth::PUBLIC_PATHS). Signed-in submissions attach user_id;
  # anonymous submissions accepted. Honeypot field rejects bots
  # silently (no specific error message — denying script feedback).
  get '/contact' do
    @page_title  = 'Contact'
    @public_page = true
    @subject = @body = @reply_to = ''
    erb :contact
  end

  post '/contact' do
    # Honeypot — bots autofill every input. Humans never see this
    # field (display:none in the view). On a match: pretend success
    # so the bot's heuristics see "submitted OK" and don't retry.
    if params['website'].to_s.strip != ''
      AppLogger.info('contact_honeypot_caught', ip: request.ip)
      redirect to('/contact?sent=1')
    end

    @subject  = params['subject'].to_s.strip[0, SupportMessagesStore::SUBJECT_MAX]
    @body     = params['body'].to_s.strip[0, SupportMessagesStore::BODY_MAX]
    @reply_to = params['reply_to'].to_s.strip[0, SupportMessagesStore::REPLY_TO_MAX]

    if @body.empty?
      @error = 'Message is required.'
      @page_title  = 'Contact'
      @public_page = true
      halt 400, erb(:contact)
    end

    SupportMessagesStore.create!(
      user_id:  signed_in? ? current_user_id : nil,
      subject:  @subject.empty?  ? nil : @subject,
      body:     @body,
      reply_to: @reply_to.empty? ? nil : @reply_to
    )
    AppLogger.info('contact_submitted',
                   signed_in: signed_in?,
                   has_subject: !@subject.empty?,
                   has_reply_to: !@reply_to.empty?)
    redirect to('/contact?sent=1')
  end

  # Pre-launch — crawler-facing files. robots.txt disallows the
  # authed surface (anything user-scoped); sitemap.xml lists only
  # the public marketing pages. Both served from Sinatra so we can
  # generate the dates dynamically; not heavy enough to need a
  # static cache layer.
  get '/robots.txt' do
    content_type 'text/plain'
    <<~ROBOTS
      # Feeder — public RSS aggregation
      # Public pages are crawlable; user-scoped surface is blocked.
      User-agent: *
      Disallow: /admin
      Disallow: /admin/
      Disallow: /api/
      Disallow: /account
      Disallow: /account/
      Disallow: /articles
      Disallow: /article/
      Disallow: /bookmarks
      Disallow: /digests
      Disallow: /feeds
      Disallow: /podcasts
      Disallow: /youtube
      Disallow: /sports
      Disallow: /search
      Disallow: /tags
      Disallow: /topics
      Disallow: /triage
      Disallow: /whats-on
      Disallow: /bus
      Disallow: /sign-out
      Disallow: /refresh/

      Sitemap: #{request.base_url}/sitemap.xml
    ROBOTS
  end

  get '/sitemap.xml' do
    content_type 'application/xml'
    base = request.base_url
    pages = [
      ['/',         1.0],
      ['/about',    0.8],
      ['/privacy',  0.5],
      ['/terms',    0.5],
      ['/contact',  0.5],
      ['/sign-up',  0.7],
      ['/sign-in',  0.5]
    ]
    lastmod = Time.now.utc.strftime('%Y-%m-%d')
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      #{pages.map { |path, pri| "  <url><loc>#{base}#{path}</loc><lastmod>#{lastmod}</lastmod><priority>#{pri}</priority></url>" }.join("\n")}
      </urlset>
    XML
  end

  # ===================================================================
  # Phase A1 (consumer auth). Passkey-only sign-up + sign-in + recovery.
  # Two HTML page shells (/sign-up, /sign-in), one logout POST, plus
  # five JSON endpoints that drive the WebAuthn ceremonies from
  # public/auth.js.
  # ===================================================================

  get '/sign-up' do
    @page_title  = 'Sign up'
    @public_page = true
    redirect to('/') if signed_in?  # bounce signed-in users home
    erb :sign_up
  end

  get '/sign-in' do
    @page_title  = 'Sign in'
    @public_page = true
    redirect to('/') if signed_in?
    erb :sign_in
  end

  post '/sign-out' do
    sign_out!
    redirect to('/')
  end

  # Step 1 of registration ceremony. Validate the requested username,
  # short-circuit if it's taken, otherwise emit a fresh
  # PublicKeyCredentialCreationOptions object. The challenge + intended
  # username are stashed in the session so step 2 can verify them.
  post '/api/auth/register/options' do
    content_type :json
    body = parse_json_body
    halt 400, JSON.generate(error: 'invalid JSON body') unless body.is_a?(Hash)

    username = UsersStore.normalize_username(body['username'].to_s)
    unless UsersStore.valid_username?(username)
      halt 400, JSON.generate(error: UsersStore::USERNAME_RULE)
    end
    if UsersStore.find_by_username(username)
      halt 409, JSON.generate(error: 'That username is already taken.')
    end

    options = WebAuthn::Credential.options_for_create(
      user: {
        id:           WebAuthn.generate_user_id,
        name:         username,
        display_name: body['display_name'].to_s.strip.empty? ? username : body['display_name'].to_s.strip
      },
      authenticator_selection: { user_verification: 'preferred' },
      exclude: WebauthnCredentialsStore.find_by_credential_id(nil).is_a?(Hash) ? [] : []  # no excludes for a brand-new user
    )

    session[:webauthn_register] = {
      challenge:    options.challenge,
      username:     username,
      display_name: body['display_name'].to_s.strip
    }
    JSON.generate(publicKey: options.as_json)
  end

  # Step 2 of registration ceremony. Verify the attestation,
  # persist user + credential rows, mint recovery codes, and return
  # them in the response body so the client can render the
  # "save these" screen. Codes are surfaced ONCE — there's no
  # "show me my codes again" endpoint by design.
  post '/api/auth/register/verify' do
    content_type :json
    stash = session.delete(:webauthn_register)
    halt 400, JSON.generate(error: 'No registration in progress — start over.') unless stash

    body = parse_json_body
    halt 400, JSON.generate(error: 'invalid JSON body') unless body.is_a?(Hash)

    credential = WebAuthn::Credential.from_create(body)
    begin
      credential.verify(stash[:challenge])
    rescue WebAuthn::Error => e
      AppLogger.warn('webauthn_register_failed', error: e.class.name, message: e.message)
      halt 400, JSON.generate(error: 'Passkey verification failed. Try again.')
    end

    # Idempotency last-mile: another request could have grabbed the
    # username while the ceremony was in flight. Re-check before insert.
    if UsersStore.find_by_username(stash[:username])
      halt 409, JSON.generate(error: 'That username was taken while you were signing up. Try a different one.')
    end

    user = UsersStore.create(username: stash[:username], display_name: stash[:display_name])
    WebauthnCredentialsStore.register!(
      user_id:       user['id'],
      credential_id: credential.id,
      public_key:    credential.public_key,
      sign_count:    credential.sign_count,
      transports:    body.dig('response', 'transports')
    )
    codes = RecoveryCodesStore.mint_for!(user_id: user['id'])
    sign_in!(user)

    JSON.generate(ok: true, recovery_codes: codes, username: user['username'])
  end

  # Step 1 of authentication ceremony. For a given username, emit
  # PublicKeyCredentialRequestOptions naming that user's registered
  # credentials. We don't 404 unknown users — saying "no such user"
  # would let an attacker enumerate. Same response shape either way;
  # an unknown user yields an empty allow-list and the ceremony fails
  # client-side with a generic message.
  post '/api/auth/login/options' do
    content_type :json
    body = parse_json_body
    halt 400, JSON.generate(error: 'invalid JSON body') unless body.is_a?(Hash)

    username = UsersStore.normalize_username(body['username'].to_s)
    user     = UsersStore.find_by_username(username)
    creds    = user ? WebauthnCredentialsStore.for_user(user['id']) : []

    options = WebAuthn::Credential.options_for_get(
      allow: creds.map { |c| c['credential_id'] },
      user_verification: 'preferred'
    )

    session[:webauthn_login] = {
      challenge: options.challenge,
      user_id:   user && user['id']
    }
    JSON.generate(publicKey: options.as_json)
  end

  # Step 2 of authentication ceremony.
  post '/api/auth/login/verify' do
    content_type :json
    stash = session.delete(:webauthn_login)
    halt 400, JSON.generate(error: 'No sign-in in progress — start over.') unless stash

    body = parse_json_body
    halt 400, JSON.generate(error: 'invalid JSON body') unless body.is_a?(Hash)

    credential = WebAuthn::Credential.from_get(body)
    cred_row   = WebauthnCredentialsStore.find_by_credential_id(credential.id)
    halt 401, JSON.generate(error: 'No such passkey.') unless cred_row

    # The stashed user_id (from the GET-options request) must match
    # the credential's actual owner. Defends against a swap where the
    # client claims username A but then signs with B's credential.
    if stash[:user_id] && stash[:user_id].to_i != cred_row['user_id'].to_i
      halt 401, JSON.generate(error: 'Passkey does not belong to that account.')
    end

    begin
      credential.verify(
        stash[:challenge],
        public_key: cred_row['public_key'],
        sign_count: cred_row['sign_count']
      )
    # OpenSSL::PKey::PKeyError isn't a WebAuthn::Error subclass — when
    # the signature is tampered the underlying OpenSSL.verify call
    # raises directly. Catch both so a malformed assertion 401s
    # instead of 500ing.
    rescue WebAuthn::Error, OpenSSL::PKey::PKeyError => e
      AppLogger.warn('webauthn_login_failed', error: e.class.name, message: e.message)
      halt 401, JSON.generate(error: 'Passkey verification failed.')
    end

    WebauthnCredentialsStore.bump_sign_count!(credential.id, credential.sign_count)
    user = UsersStore.find(cred_row['user_id'])
    sign_in!(user)

    return_to = session.delete(:return_to) || '/'
    JSON.generate(ok: true, return_to: return_to)
  end

  # Recovery — consume a one-time code, sign the user in. The code
  # IS the credential; we don't ask for a username because the code
  # is unique across users and reveals the user_id on hash match.
  post '/api/auth/recovery' do
    content_type :json
    body = parse_json_body
    halt 400, JSON.generate(error: 'invalid JSON body') unless body.is_a?(Hash)

    user_id = RecoveryCodesStore.consume!(body['code'])
    halt 401, JSON.generate(error: 'That code is invalid or already used.') unless user_id

    user = UsersStore.find(user_id)
    halt 401, JSON.generate(error: 'That code is invalid or already used.') unless user
    sign_in!(user)

    return_to = session.delete(:return_to) || '/'
    remaining = RecoveryCodesStore.unconsumed_count_for(user_id)
    JSON.generate(ok: true, return_to: return_to, recovery_codes_remaining: remaining)
  end

  # ===================================================================
  # Account management (STUFF #29 follow-up)
  # ===================================================================
  # /account lets a signed-in user edit their display name, manage
  # their registered passkeys (list / add another / revoke), regenerate
  # the recovery-code batch, and delete their account. Routes live
  # under `/account/*` (not `/api/auth/account/*`) so the public-route
  # allowlist (`/api/auth/*` is public for the sign-in/up ceremonies)
  # doesn't accidentally expose them.

  get '/account' do
    require_signed_in!
    @page_title              = 'Account'
    @account_user            = current_user
    @account_passkeys        = WebauthnCredentialsStore.for_user(current_user_id)
    @account_recovery_remain = RecoveryCodesStore.unconsumed_count_for(current_user_id)
    @account_new_codes       = session.delete(:account_new_codes)
    @account_notice          = params['notice']
    @account_error           = params['error']
    erb :account
  end

  # Pre-launch — fulfils the privacy-policy promise: "Export your
  # data". Returns a JSON dump of every per-user row + a manifest
  # of what's intentionally excluded (publisher content, passkey
  # private keys, recovery-code plaintexts). content-disposition:
  # attachment so browsers prompt to download instead of rendering.
  get '/account/export.json' do
    require_signed_in!
    require 'base64'
    response['Content-Type']        = 'application/json; charset=utf-8'
    response['Content-Disposition'] = %(attachment; filename="feeder-export-user-#{current_user_id}-#{Date.today}.json")
    AppLogger.info('account_export', user_id: current_user_id)
    JSON.pretty_generate(AccountExport.for_user(current_user_id))
  end

  post '/account/display-name' do
    require_signed_in!
    UsersStore.update_display_name!(current_user_id, params['display_name'])
    AppLogger.info('account_display_name_updated', user_id: current_user_id)
    redirect to('/account?notice=display-name-updated')
  end

  # Step 1 of "add another passkey" ceremony. Identifies the user by
  # session (NOT by username from the body) — they're already signed in.
  # The new credential is added to webauthn_credentials_excluded so the
  # browser won't let the user accidentally register a passkey they've
  # already got registered on this device.
  post '/account/passkey/options' do
    require_signed_in!
    content_type :json
    existing = WebauthnCredentialsStore.for_user(current_user_id)

    options = WebAuthn::Credential.options_for_create(
      user: {
        id:           WebAuthn.generate_user_id,
        name:         current_user['username'],
        display_name: current_user['display_name'] || current_user['username']
      },
      authenticator_selection: { user_verification: 'preferred' },
      exclude: existing.map { |c| c['credential_id'] }
    )

    session[:webauthn_account_register] = {
      challenge: options.challenge,
      user_id:   current_user_id
    }
    JSON.generate(publicKey: options.as_json)
  end

  post '/account/passkey/verify' do
    require_signed_in!
    content_type :json
    stash = session.delete(:webauthn_account_register)
    halt 400, JSON.generate(error: 'No registration in progress — start over.') unless stash
    halt 400, JSON.generate(error: 'Session mismatch.') unless stash[:user_id].to_i == current_user_id

    body = parse_json_body
    halt 400, JSON.generate(error: 'invalid JSON body') unless body.is_a?(Hash)

    credential = WebAuthn::Credential.from_create(body)
    begin
      credential.verify(stash[:challenge])
    rescue WebAuthn::Error => e
      AppLogger.warn('account_passkey_register_failed', user_id: current_user_id,
                                                         error: e.class.name, message: e.message)
      halt 400, JSON.generate(error: 'Passkey verification failed. Try again.')
    end

    WebauthnCredentialsStore.register!(
      user_id:       current_user_id,
      credential_id: credential.id,
      public_key:    credential.public_key,
      sign_count:    credential.sign_count,
      transports:    body.dig('response', 'transports'),
      label:         body['label'].to_s.strip.empty? ? nil : body['label'].to_s.strip[0, 60]
    )
    AppLogger.info('account_passkey_registered', user_id: current_user_id, credential_id: credential.id)
    JSON.generate(ok: true)
  end

  # Lockout protection: refuse to delete the last passkey if the user
  # has zero unused recovery codes. Otherwise they'd be locked out of
  # their own account by the next browser-cache wipe.
  post '/account/passkey/:credential_id/delete' do |credential_id|
    require_signed_in!
    passkey_count = WebauthnCredentialsStore.count_for_user(current_user_id)
    recovery_left = RecoveryCodesStore.unconsumed_count_for(current_user_id)
    if passkey_count <= 1 && recovery_left.zero?
      redirect to('/account?error=last-passkey-no-recovery')
    end

    if WebauthnCredentialsStore.delete_for_user!(current_user_id, credential_id)
      AppLogger.info('account_passkey_revoked', user_id: current_user_id, credential_id: credential_id)
      redirect to('/account?notice=passkey-revoked')
    else
      redirect to('/account?error=passkey-not-found')
    end
  end

  post '/account/recovery-codes/regenerate' do
    require_signed_in!
    codes = RecoveryCodesStore.regenerate_for!(current_user_id)
    # Pass through the session so a refresh after the redirect still
    # surfaces the codes once. Cleared on the next /account GET.
    session[:account_new_codes] = codes
    AppLogger.info('account_recovery_codes_regenerated', user_id: current_user_id, count: codes.length)
    redirect to('/account?notice=recovery-codes-regenerated')
  end

  # Hard-delete the signed-in user's account. Per-user tables cascade
  # via the ON DELETE CASCADE FKs in migration 022. Shared catalog rows
  # (`feeds`, `articles`) stay so other users keep their subscriptions.
  # Confirmation gate: the form must POST `confirm_username` matching
  # the signed-in user's username exactly. Anything else 400s back to
  # /account so an accidental click can't nuke the account.
  post '/account/delete' do
    require_signed_in!
    expected = current_user['username'].to_s
    typed    = params['confirm_username'].to_s.strip.downcase
    if typed != expected
      redirect to('/account?error=delete-confirm-mismatch')
    end

    uid = current_user_id
    UsersStore.delete!(uid)
    AppLogger.info('account_deleted', user_id: uid, username: expected)
    sign_out!
    redirect to('/?notice=account-deleted')
  end

  # ===================================================================
  # First-time-user onboarding (/welcome)
  # ===================================================================
  # A signed-in user who has zero feed subscriptions lands here from
  # GET / instead of the marketing pitch. Picks a subset of topic
  # chips → POST /welcome/subscribe seeds 4-6 curated catalog feeds
  # per selected topic → redirects to /articles with a notice.

  get '/welcome' do
    require_signed_in!
    @page_title = 'Welcome'
    if FeedsStore.count_for_user(current_user_id).positive?
      redirect to('/')
    end
    @account_user = current_user
    @chips        = FeedCatalog::ONBOARDING_CHIPS
    erb :welcome
  end

  post '/welcome/subscribe' do
    require_signed_in!
    requested = Array(params['topics']).map(&:to_sym)
    selected  = requested & FeedCatalog::ONBOARDING_CHIPS.keys
    redirect to('/welcome') if selected.empty?

    inserted_count = 0
    selected.each do |topic|
      FeedCatalog.starters_for_topic(topic).each do |entry|
        feed, inserted = FeedsStore.add_for_user(
          user_id: current_user_id,
          url:     entry[:url],
          title:   entry[:title],
          fetch_interval_seconds: entry[:interval],
          topic:   FeedCatalog.topic_for(entry).to_s
        )
        next unless inserted
        inserted_count += 1
        # Same logic as /youtube/subscribe-bulk: only enqueue a
        # background fetch when the feed has never been fetched
        # before. Feeds another user already subscribed to (content
        # already imported) skip the refresh.
        FeedRefreshWorker.perform_async(feed['id']) if feed['last_fetched_at'].nil?
      end
    end

    AppLogger.info('onboarding_complete', user_id: current_user_id,
                                          topics: selected, inserted: inserted_count)
    redirect to("/articles?notice=onboarded&count=#{inserted_count}")
  end

  # /whats-on → / 301-redirect for backwards compatibility with old
  # bookmarks / nav links. The "What's On Today" experience lives at
  # / now (for returning users; anonymous still gets marketing).
  get '/whats-on' do
    redirect to('/'), 301
  end

  # /dashboard → /admin/dashboard. The operational stats / Activity
  # chart moved under /admin so / can host the more user-facing
  # What's On Today surface. Permanent 301 so any existing bookmark
  # gets cached correctly by the browser.
  get '/dashboard' do
    redirect to('/admin/dashboard'), 301
  end

  get '/admin/dashboard' do
    @page_title       = 'Dashboard'
    @articles         = ArticlesStore.recent(current_user_id, limit: 20, state: :unread)
    @feeds_by_id      = FeedsStore.for_user(current_user_id).each_with_object({}) { |f, h| h[f['id']] = f }
    @article_count    = ArticlesStore.count_for_user(current_user_id)
    @unread_count     = ReadStateStore.unread_count(current_user_id)
    @bookmark_count   = ReadStateStore.bookmarked_count(current_user_id)
    @feed_count       = FeedsStore.count_for_user(current_user_id)
    @degraded         = HealthRegistry.degraded?
    @activity_window  = Pruner.effective_retention_days
    @daily_counts     = ArticlesStore.daily_counts(current_user_id, days: @activity_window)
    @top_feeds        = ArticlesStore.counts_by_feed(current_user_id, limit: 10)
    @top_tags_week    = TagsStore.top_in_window(current_user_id, days: 7, limit: 8)
    @topic_clusters   = TopicClusters.recent(days: 14, limit: 8)
    erb :dashboard
  end

  ARTICLES_STATE_FILTERS = %i[all unread bookmarked archived].freeze

  get '/articles' do
    @page_title  = 'Articles'
    @page        = [params['page'].to_i, 1].max
    @per_page    = 50
    offset       = (@page - 1) * @per_page
    feed_id      = params['feed_id'].to_i
    tag_id       = params['tag'].to_i
    @feed_filter = feed_id.positive? ? FeedsStore.find(feed_id) : nil
    @tag_filter  = tag_id.positive?  ? TagsStore.find(current_user_id, tag_id) : nil

    @state_filter = (params['state'] || 'all').to_sym
    @state_filter = :all unless ARTICLES_STATE_FILTERS.include?(@state_filter)

    @kind_filter = params['kind'].to_s == 'podcast' ? :podcast : :all
    @view_filter = params['view'].to_s == 'skim' ? :skim : :default
    # Sports Phase S1 — top-level topic filter. nil = unfiltered.
    # See sanitize_topic_filter helper for the validator.
    @topic_filter = sanitize_topic_filter(params['topic'])
    @sort_filter = params['sort'].to_s == 'relevance' ? :relevance : :chronological

    @articles = if @tag_filter
                  ArticlesStore.for_tag(current_user_id, tag_id, limit: @per_page, offset: offset, state: @state_filter)
                elsif @feed_filter
                  ArticlesStore.for_feed(current_user_id, feed_id, limit: @per_page, offset: offset, state: @state_filter)
                elsif @sort_filter == :relevance
                  @state_filter = :unread
                  Recommendation::ForYou.score_window(current_user_id,
                                                      state: :unread, kind: @kind_filter,
                                                      topic: @topic_filter,
                                                      limit: @per_page, offset: offset)
                else
                  ArticlesStore.recent(
                    current_user_id,
                    limit: @per_page, offset: offset,
                    state: @state_filter, kind: @kind_filter,
                    topic: @topic_filter
                  )
                end

    @feeds_by_id     = FeedsStore.for_user(current_user_id).each_with_object({}) { |f, h| h[f['id']] = f }
    @tags_by_article = TagsStore.tags_for_articles(current_user_id, @articles.map { |a| a['id'] })
    # Skim mode shows a summary line per row — batch-fetch the cached
    # summaries for the page so the view doesn't N+1 SummaryStore.find.
    @summaries_by_article_id = if @view_filter == :skim
                                 SummaryStore.find_for_ids(@articles.map { |a| a['id'] })
                               else
                                 {}
                               end
    # STUFF.md follow-up — context strip under the page header. Cheap
    # one-shot queries: which feed is most active in the last 24h
    # (used by view) and the absolute count of articles in the user's
    # corpus (used in the "of <N> total" line). Total-for-current-
    # filter is harder to compute without a parallel COUNT query;
    # leaving that as a follow-up.
    @articles_total       = ArticlesStore.count_for_user(current_user_id)
    @most_active_24h_feed = articles_most_active_feed_24h
    erb :articles
  end

  # Dedicated bookmarks surface. The /articles route already supports
  # ?state=bookmarked, but URL-hacking it isn't discoverable — users
  # save articles with no clear path back to them. /bookmarks pins
  # the state filter, sets a bookmarks-specific page header + empty
  # state, and gets its own top-level nav link. Renders the existing
  # articles.erb view (with @bookmarks_page = true so the header /
  # empty-state copy adjust); reuses the bulk-action toolbar, skim
  # mode, pagination — every affordance /articles has.
  BOOKMARKS_PER_PAGE = 50

  get '/bookmarks' do
    @page_title     = 'Bookmarks'
    @bookmarks_page = true
    @page           = [params['page'].to_i, 1].max
    @per_page       = BOOKMARKS_PER_PAGE
    offset          = (@page - 1) * @per_page

    @state_filter = :bookmarked
    @kind_filter  = :all
    @view_filter  = params['view'].to_s == 'skim' ? :skim : :default
    @sort_filter  = :chronological
    @topic_filter = nil
    @feed_filter  = nil
    @tag_filter   = nil

    @articles = ArticlesStore.recent(
      current_user_id,
      limit: @per_page, offset: offset,
      state: :bookmarked
    )

    @feeds_by_id     = FeedsStore.for_user(current_user_id).each_with_object({}) { |f, h| h[f['id']] = f }
    @tags_by_article = TagsStore.tags_for_articles(current_user_id, @articles.map { |a| a['id'] })
    @summaries_by_article_id = if @view_filter == :skim
                                 SummaryStore.find_for_ids(@articles.map { |a| a['id'] })
                               else
                                 {}
                               end
    @articles_total       = ArticlesStore.count_for_user(current_user_id)
    @most_active_24h_feed = nil  # context strip is hidden on bookmarks
    erb :articles
  end

  # Browse view across every subscribed podcast feed. Top of the page
  # surfaces each show with its episode count + latest-episode age,
  # so the user can spot the freshest show at a glance. Below, the
  # most recent N episodes across all shows render as cards — each
  # card links to /article/:uid where the player lives.
  # Bus mode — "what's short enough for my commute?" Lists recent
  # podcast episodes whose runtime is at-or-under the cutoff. Default
  # 15 minutes; override via ?max_minutes= for a longer commute.
  BUS_DEFAULT_MAX_MINUTES = 15
  BUS_MAX_MINUTES_LIMIT   = 90  # absolute ceiling so a malicious URL can't pull the full corpus
  BUS_LIMIT               = 25

  get '/bus' do
    @page_title       = 'Bus mode'
    requested_minutes = params['max_minutes'].to_s
    @max_minutes      = requested_minutes.match?(/\A\d+\z/) ? requested_minutes.to_i.clamp(1, BUS_MAX_MINUTES_LIMIT) : BUS_DEFAULT_MAX_MINUTES
    @cutoff_seconds   = @max_minutes * 60

    @episodes    = ArticlesStore.recent(
      current_user_id,
      limit:                BUS_LIMIT,
      kind:                 :podcast,
      max_duration_seconds: @cutoff_seconds
    )
    @feeds_by_id = FeedsStore.for_user(current_user_id).each_with_object({}) { |f, h| h[f['id']] = f }
    erb :bus
  end

  get '/podcasts' do
    @page_title       = 'Podcasts'
    @shows            = ArticlesStore.podcast_feeds(current_user_id)
    @recent_episodes  = ArticlesStore.recent(current_user_id, limit: 25, kind: :podcast)
    @feeds_by_id      = FeedsStore.for_user(current_user_id).each_with_object({}) { |f, h| h[f['id']] = f }
    erb :podcasts
  end

  # STUFF #26 — YouTube channel grid. Mirrors /podcasts in shape:
  # one card per subscribed YouTube channel feed (matched by the
  # canonical channel-feed URL pattern), with cover art, recent video
  # count, latest-video age, and a small "↗ Channel" link that opens
  # the channel on YouTube in a new tab. Card click → /youtube/:feed_id.
  # STUFF #65 — webcomics index. Mirrors /podcasts + /youtube in shape:
  # one tile per subscribed humor-topic feed, ordered by latest-panel
  # date desc. Tile shows the latest panel image (or the feed's cover
  # art as a fallback) + title + relative time. Click → /comics/:id
  # panel list for that series (STUFF #66 behavior — was "jump to
  # latest panel", changed so users see the series archive).
  get '/comics' do
    @page_title    = 'Comics'
    @series        = ArticlesStore.comic_feeds(current_user_id)
    @recent_comics = ArticlesStore.recent(current_user_id, limit: 12, topic: 'humor')
    # STUFF #66 — needed by views/comics.erb to render the source
    # series name on each Recent-panels row. Mirrors the @feeds_by_id
    # plumbing in /podcasts + /youtube.
    @feeds_by_id   = FeedsStore.for_user(current_user_id).each_with_object({}) { |f, h| h[f['id']] = f }
    erb :comics
  end

  # STUFF #66 — per-series panel list. Patterns after /youtube/:feed_id:
  # subscription + topic guard, then `recent_for_feed` for the most
  # recent panels. Click any panel → /article/:uid reader (where the
  # comic-hero + lightbox already handle the actual viewing).
  COMIC_SERIES_PANELS_LIMIT = 30
  get '/comics/:feed_id' do |feed_id|
    @feed = FeedsStore.find(feed_id.to_i)
    halt 404, erb(:article_not_found) unless @feed
    unless FeedsStore.subscribed?(current_user_id, @feed['id'])
      halt 404, erb(:article_not_found)
    end
    unless @feed['topic'].to_s == 'humor'
      halt 404, erb(:article_not_found)
    end

    @page_title = @feed['title'] || 'Comic series'
    @panels     = ArticlesStore.recent_for_feed(current_user_id, @feed['id'], limit: COMIC_SERIES_PANELS_LIMIT)
    erb :comic_series
  end

  get '/youtube' do
    @page_title    = 'YouTube'
    @channels      = ArticlesStore.youtube_channels(current_user_id)
    # STUFF #50 — recent-videos grid (mirrors /podcasts' recent-episodes
    # section). Every YouTube video has a guaranteed hqdefault.jpg
    # thumbnail derivable from its URL, so this section gives the page
    # a steady image-led feel even when individual channels lack a
    # cover image.
    @recent_videos = ArticlesStore.recent(current_user_id, limit: 12, kind: :youtube)
    @feeds_by_id   = FeedsStore.for_user(current_user_id).each_with_object({}) { |f, h| h[f['id']] = f }
    erb :youtube
  end

  # STUFF #30 — bulk-subscribe to YouTube channels via @handles / URLs.
  # Accepts a newline-separated list in `channels` form param; resolves
  # each line via Providers::YouTubeChannelResolver (channel-page scrape
  # for @handles, direct feed-XML fetch for /channel/UC… URLs); routes
  # the resolved canonical feed URL through the existing
  # FeedsStore.add_for_user flow; re-renders /youtube with a per-line
  # result panel so the user sees which lines succeeded vs failed.
  YOUTUBE_BULK_ADD_MAX = 25  # synchronous request — keep bounded
  post '/youtube/subscribe-bulk' do
    @page_title = 'YouTube'
    raw_lines   = (params['channels'] || '').split(/\r?\n/).map(&:strip).reject(&:empty?)
    if raw_lines.empty?
      @bulk_error = 'Paste at least one channel handle or URL.'
      @channels   = ArticlesStore.youtube_channels(current_user_id)
      return erb :youtube
    end

    truncated = raw_lines.length > YOUTUBE_BULK_ADD_MAX
    lines     = raw_lines.first(YOUTUBE_BULK_ADD_MAX)

    @bulk_results = lines.map do |line|
      result = Providers::YouTubeChannelResolver.resolve(line)
      case result.status
      when :ok
        feed, inserted = FeedsStore.add_for_user(
          user_id: current_user_id,
          url:     result.feed_url,
          title:   result.title,
          fetch_interval_seconds: FeedsStore::PUBLISHER_INTERVAL,
          topic:   'general'
        )
        # Brand-new feeds (never fetched yet — articles table is empty
        # for this feed_id) get a background refresh kicked off so the
        # /youtube grid is populated within ~30s instead of waiting for
        # the next scheduler tick. If another user was already subscribed
        # to this feed, content is already imported and no refresh is
        # needed.
        needs_fetch = inserted && feed['last_fetched_at'].nil?
        FeedRefreshWorker.perform_async(feed['id']) if needs_fetch

        AppLogger.info('youtube_bulk_add', input: line, channel_id: result.channel_id,
                                            title: result.title, inserted: inserted,
                                            queued_fetch: needs_fetch)
        status = if !inserted
                   :already
                 elsif needs_fetch
                   :subscribed_pending_fetch
                 else
                   :subscribed
                 end
        { input: line, status: status, title: result.title }
      when :not_found
        { input: line, status: :not_found, message: result.error }
      else
        { input: line, status: :error, message: result.error }
      end
    end

    @bulk_truncated = truncated
    @bulk_total     = raw_lines.length
    @channels       = ArticlesStore.youtube_channels(current_user_id)
    erb :youtube
  end

  # Single-channel page: the 10 most recent videos for one YouTube
  # feed. Tiles use the existing hqdefault thumbnail helper +
  # link to /article/:uid where the player is already embedded
  # (shipped earlier in STUFF #19).
  YOUTUBE_CHANNEL_VIDEOS_LIMIT = 10
  get '/youtube/:feed_id' do |feed_id|
    @feed = FeedsStore.find(feed_id.to_i)
    halt 404, erb(:article_not_found) unless @feed
    unless FeedsStore.subscribed?(current_user_id, @feed['id'])
      halt 404, erb(:article_not_found)
    end
    unless @feed['url'].to_s.include?('youtube.com/feeds/videos.xml')
      halt 404, erb(:article_not_found)
    end

    @page_title    = @feed['title'] || 'YouTube channel'
    @videos        = ArticlesStore.recent_for_feed(current_user_id, @feed['id'], limit: YOUTUBE_CHANNEL_VIDEOS_LIMIT)
    @channel_url   = youtube_channel_url_from(@feed['url'])
    erb :youtube_channel
  end

  # Sports overview (Phase S5, news-only v1). Aggregates the user's
  # subscribed sports feeds + recent articles, broken out per sport
  # (NFL / NBA / Soccer / Rugby / Tennis). Live scores / results /
  # upcoming come later when Phase S3+ adds the structured-data
  # tables; until then, this is the news-side equivalent of the
  # podcast show grid.
  get '/sports' do
    @page_title  = 'Sports'
    @feeds_by_id = FeedsStore.for_user(current_user_id).each_with_object({}) { |f, h| h[f['id']] = f }
    sports_feeds = @feeds_by_id.values.select { |f| f['topic'] == 'sports' }

    # Per-sport subscribed-feed list, keyed by sub-category from the
    # catalog where available (falls back to :other for any
    # subscribed-but-uncatalogued URL).
    @feeds_by_sport = sports_feeds.group_by do |f|
      entry = FeedCatalog.find_by_url(f['url'])
      entry ? entry[:category] : :other
    end

    # Per-sport recent article window. Single SQL pull (topic=sports)
    # then bucket in Ruby — cheaper than N queries when most users
    # only follow a couple of sports.
    @recent_by_sport = Hash.new { |h, k| h[k] = [] }
    if sports_feeds.any?
      ArticlesStore.recent(current_user_id, limit: 100, topic: 'sports').each do |a|
        feed  = @feeds_by_id[a['feed_id']]
        next unless feed
        entry = FeedCatalog.find_by_url(feed['url'])
        sport = entry ? entry[:category] : :other
        @recent_by_sport[sport] << a if @recent_by_sport[sport].length < 8
      end
    end
    # Batch-load cached summaries for the rendered articles so the
    # inline-summary line on each card doesn't N+1 SummaryStore.find.
    rendered_ids = @recent_by_sport.values.flatten.map { |a| a['id'] }
    @summaries_by_article_id = SummaryStore.find_for_ids(rendered_ids)

    # Sports sub-categories from the catalog, in declaration order.
    @sports_sub_categories = FeedCatalog::CATEGORIES.keys.select do |cat|
      FeedCatalog::CATEGORY_TO_TOPIC[cat] == :sports
    end
    # Team buttons in the TOC — only render teams whose feed_urls
    # overlap with the user's actual subscriptions. No point linking
    # to /sports/team/eagles if the user hasn't subscribed to a
    # single Eagles feed.
    curated_with_subs = SportsTeams.all.select do |team|
      SportsTeams.subscribed_feeds_for(team).any?
    end
    # STUFF #68 — extend the score-tile + TOC team-button rows to
    # include DB-side teams the user follows via sports_follows.
    # Without this, following the Phillies (or any team outside the
    # curated 5) leaves no panel on /sports. Resolves each follow's
    # slug against sports_teams; skips the ones already present in
    # the curated set so they don't render twice.
    curated_slugs = curated_with_subs.map { |t| t[:slug] }.to_set
    db_followed_teams = SportsFollowsStore.for_kind(current_user_id, 'team')
                                          .map { |f| f['value'] }
                                          .reject { |slug| curated_slugs.include?(slug) }
                                          .filter_map { |slug| SportsTeamsStore.find_by_slug(slug) }
                                          .map { |row| db_team_as_curated(row) }
    @teams_with_subs = curated_with_subs + db_followed_teams
    # STUFF.md #9 — score tiles at the top of /sports. Pull last
    # final per followed team from the structured-data layer (S3+S4)
    # and surface as score tiles. Empty when no follows or no
    # finals synced yet.
    @last_finals_by_team = build_last_finals(@teams_with_subs)
    # S8 — leagues the user can navigate to. Anything with synced
    # standings is fair game: NFL/NBA/MLS (followed-team leagues)
    # plus globally-interesting tournaments like the FIFA World Cup
    # (which the user doesn't follow a specific team in but asked
    # to be able to navigate to).
    @leagues_with_standings = SportsLeaguesStore.all.select do |lg|
      Database.connection.execute(
        'SELECT 1 FROM sports_standings WHERE league_id = ? LIMIT 1', [lg['id']]
      ).any?
    end
    # STUFF #70 — followed tournaments (sports_follows.kind='league').
    # Resolve each follow slug to its DB row + catalog metadata so the
    # view can render a tile per tournament with name, sport emoji,
    # blurb, and a link to /sports/league/:slug. Skips orphan follows
    # (slug doesn't resolve to a sports_leagues row).
    followed_league_slugs = SportsFollowsStore.for_kind(current_user_id, 'league').map { |f| f['value'] }
    @followed_tournaments = followed_league_slugs.filter_map do |slug|
      row     = SportsLeaguesStore.find_by_slug(slug)
      next nil unless row
      catalog = SportsCatalog.all_leagues.find { |lg| lg[:slug] == slug }
      {
        row:     row,
        catalog: catalog,
        sport:   catalog && SportsCatalog.find_sport(catalog[:sport_slug])
      }
    end
    erb :sports
  end

  # Sports Phase S7 — tennis rankings landing.
  #
  # Two side-by-side tables (ATP top N + WTA top N) so the user
  # can scan the men's and women's tour states. Click a player's
  # name → drill into /sports/player/:slug.
  get '/sports/tennis' do
    @page_title = 'Tennis rankings'
    limit_raw   = params['limit'].to_s
    @limit      = (limit_raw.match?(/\A\d+\z/) ? limit_raw.to_i : 50).clamp(1, 150)
    # STUFF #46 — opportunistic ESPN refresh on page load. If the
    # last sync per-tour is > 12h ago (or never), pull fresh
    # rankings inline. Adds ~1s to the first request after the
    # TTL window; cached for everyone after. Bypass with
    # ?skip_refresh=1 (for debugging the empty-state path).
    unless params['skip_refresh'] == '1'
      %w[atp wta].each do |tour|
        SportsPlayersStore.refresh_if_stale!(tour: tour)
      rescue StandardError => e
        AppLogger.warn('tennis_autosync', tour: tour, status: :error, message: e.message)
      end
    end
    @atp        = SportsPlayersStore.top_ranked(tour: 'atp', limit: @limit)
    @wta        = SportsPlayersStore.top_ranked(tour: 'wta', limit: @limit)
    # Phase S7 follow-up — followed-player slugs (so view can mark
    # the ★ chip on each row + render the "My followed players"
    # callout above the rankings).
    @followed_player_slugs = SportsFollowsStore.for_kind(current_user_id, 'player').map { |f| f['value'] }.to_set
    @followed_players = @followed_player_slugs.filter_map do |slug|
      SportsPlayersStore.find_by_slug(slug)
    end
    erb :sports_tennis
  end

  # Sports Phase S7 — single-player detail page.
  get '/sports/player/:slug' do |slug|
    # Catalog players (notable-player chips on team cards in #52)
    # are upserted to sports_players on first click — see
    # ensure_catalog_player_by_slug for the lookup walk.
    @player = SportsPlayersStore.find_by_slug(slug) || ensure_catalog_player_by_slug(slug)
    halt 404, erb(:article_not_found) unless @player
    @page_title    = @player['full_name']
    # ESPN player-card link reconstructed from external_id + slug.
    # Only meaningful for tennis players synced from ESPN; catalog
    # players (source_provider='catalog') don't have an ESPN profile
    # so the view hides the section.
    @espn_url      = "https://www.espn.com/tennis/player/_/id/#{@player['external_id']}/#{slug}" if @player['tour']
    @is_followed   = SportsFollowsStore.follow?(current_user_id, 'player', slug)

    # STUFF #52.1 — for catalog players, surface the back-link to
    # their team page. The slug is "{team_slug}-{name_slug}" so we
    # match the team by prefix.
    if @player['source_provider'] == 'catalog'
      @catalog_team = SportsCatalog.all_teams.find do |t|
        @player['external_id'].to_s.start_with?("#{t[:slug]}-")
      end
    end
    # S7 follow-up #2 — articles mentioning the player. Refresh
    # if the cache is stale (TTL 1h), then read from the join table.
    SportsEntityArticlesStore.refresh_for(
      kind: 'player', entity_id: @player['id'], name: @player['full_name']
    )
    @related_articles = SportsEntityArticlesStore.for_entity(
      kind: 'player', entity_id: @player['id'], limit: 30
    )
    @feeds_by_id = FeedsStore.for_user(current_user_id).each_with_object({}) { |f, h| h[f['id']] = f }
    @summaries_by_article_id = SummaryStore.find_for_ids(@related_articles.map { |a| a['id'] })
    erb :sports_player
  end

  # Sports Phase S7 follow-up — tennis player follows. Both
  # endpoints are idempotent (re-follow / re-unfollow no-ops) so a
  # mis-clicked button doesn't 500.
  post '/sports/players/follow' do
    slug = params['slug'].to_s
    halt 400, 'slug required' if slug.empty?
    halt 404 unless SportsPlayersStore.find_by_slug(slug)
    SportsFollowsStore.add(user_id: current_user_id, kind: 'player', value: slug)
    AppLogger.info('player_follow', slug: slug)
    return sports_follow_json(slug: slug, kind: 'player', followed: true) if wants_json?
    redirect to(params['return_to'] || "/sports/player/#{slug}")
  end

  post '/sports/players/unfollow' do
    slug = params['slug'].to_s
    halt 400, 'slug required' if slug.empty?
    SportsFollowsStore.remove(user_id: current_user_id, kind: 'player', value: slug)
    AppLogger.info('player_unfollow', slug: slug)
    return sports_follow_json(slug: slug, kind: 'player', followed: false) if wants_json?
    redirect to(params['return_to'] || "/sports/player/#{slug}")
  end

  # STUFF #43 — team management. /sports/manage lists every team in
  # the catalog grouped by league, with follow/unfollow buttons. Solves
  # the prod gap where a freshly-signed-up user can't follow any team
  # (the 4 hardcoded follows in seed_sports_data.rb were for user 1
  # only, and even with full-catalog seeds users couldn't toggle them
  # through the UI).
  # STUFF #52 — /sports/manage now reads the hand-curated
  # SportsCatalog. Three views layered top-down:
  #   /sports/manage                       → sport-first landing (chips)
  #   /sports/manage/:sport                → leagues in this sport
  #   /sports/manage/:sport/:league        → teams in this league
  # Follow actions upsert the catalog entry into sports_leagues +
  # sports_teams on demand so the live-scores pipeline still finds
  # what it needs in the DB without bulk-seeding 100s of teams.
  get '/sports/manage' do
    @page_title    = 'Manage sports'
    # Pass the catalog through as an instance var so the ERB's
    # constant lookup doesn't resolve to TechFeedReader::SportsCatalog
    # (where it doesn't live).
    @sports         = SportsCatalog::SPORTS
    @followed_slugs = SportsFollowsStore.for_kind(current_user_id, 'team')
                                        .map { |f| f['value'] }.to_set
    erb :sports_manage
  end

  get '/sports/manage/:sport' do |sport_slug|
    @sport = SportsCatalog.find_sport(sport_slug)
    halt 404, 'no such sport' unless @sport
    @page_title    = "#{@sport[:name]} — Manage"
    @followed_slugs = SportsFollowsStore.for_kind(current_user_id, 'team')
                                        .map { |f| f['value'] }.to_set
    # STUFF #70 — tournament-shape leagues are follow-toggleable on
    # this page (vs. season leagues which drill into team grids).
    # Pre-load the user's league follows so the button can flip
    # state alongside the team-follow buttons in the same view.
    @followed_league_slugs = SportsFollowsStore.for_kind(current_user_id, 'league')
                                                .map { |f| f['value'] }.to_set
    erb :sports_manage_sport
  end

  get '/sports/manage/:sport/:league' do |sport_slug, league_slug|
    @sport  = SportsCatalog.find_sport(sport_slug)
    @league = SportsCatalog.find_league(sport_slug, league_slug)
    halt 404, 'no such league' unless @sport && @league
    @page_title    = "#{@league[:name]} — Manage"
    @followed_slugs = SportsFollowsStore.for_kind(current_user_id, 'team')
                                        .map { |f| f['value'] }.to_set
    @followed_league_slugs = SportsFollowsStore.for_kind(current_user_id, 'league')
                                                .map { |f| f['value'] }.to_set
    # STUFF #75 — for api-sports leagues the catalog carries teams:[]
    # (teams auto-populate from match data on first sync). Load from DB
    # so the manage page can show a follow grid once data exists.
    @db_teams = []
    if (@league[:teams] || []).empty? && @league[:source_provider] == 'api-sports'
      league_row = SportsLeaguesStore.find_by_slug(@league[:slug])
      @db_teams = SportsTeamsStore.for_league(league_row['id']).sort_by { |t| t['name'] } if league_row
    end
    # STUFF #52 PR3 — curated RSS feeds for this league + which the
    # user is already subscribed to (so the button can flip).
    @league_feeds   = FeedCatalog.feeds_for_sports_league(@league[:slug])
    @subscribed_urls = FeedsStore.for_user(current_user_id)
                                 .map { |f| f['url'] }.to_set
    erb :sports_manage_league
  end

  # STUFF #52 PR3 — one-click subscribe from a sports league page.
  # Validates the URL is in the catalog (no arbitrary URLs accepted),
  # subscribes the user (idempotent), and returns to the page they
  # came from. Mirrors POST /feeds/catalog/add but redirects back to
  # the league instead of /feeds.
  post '/sports/feeds/subscribe' do
    url   = params['url'].to_s.strip
    entry = FeedCatalog.find_by_url(url)
    return_to = params['return_to'].to_s
    return_to = '/sports/manage' if return_to.empty?
    halt 422, 'not in catalog' unless entry

    _feed, inserted = FeedsStore.add_for_user(
      user_id: current_user_id,
      url: entry[:url], title: entry[:title],
      fetch_interval_seconds: entry[:interval],
      topic: FeedCatalog.topic_for(entry).to_s
    )
    AppLogger.info(
      inserted ? 'sports_feed_subscribed' : 'sports_feed_already_subscribed',
      url: entry[:url], title: entry[:title]
    )
    redirect to(return_to)
  end

  # POST /sports/teams/follow — add the team to the user's follows
  # AND enqueue a Sidekiq job to fetch the team's recent schedule +
  # results from ESPN. Without the eager fetch, a freshly-followed
  # team's score tiles + recent results would stay empty until the
  # next nightly sync. STUFF #52: if the team isn't in the DB yet
  # (catalog-only), upsert it (and its league) from SportsCatalog
  # before adding the follow.
  post '/sports/teams/follow' do
    slug = params['slug'].to_s
    halt 400, 'slug required' if slug.empty?
    team = SportsTeamsStore.find_by_slug(slug) || ensure_catalog_team_in_db(slug)
    halt 404, 'team not found' unless team
    SportsFollowsStore.add(user_id: current_user_id, kind: 'team', value: slug)
    begin
      SportsTeamFetchWorker.perform_async(team['id']) if team['source_provider'] == 'espn'
    rescue StandardError => e
      AppLogger.warn('team_follow_enqueue_failed', slug: slug, message: e.message)
    end
    AppLogger.info('team_follow', slug: slug, team_id: team['id'])
    return sports_follow_json(slug: slug, kind: 'team', followed: true) if wants_json?
    redirect to(params['return_to'] || '/sports/manage')
  end

  post '/sports/teams/unfollow' do
    slug = params['slug'].to_s
    halt 400, 'slug required' if slug.empty?
    SportsFollowsStore.remove(user_id: current_user_id, kind: 'team', value: slug)
    AppLogger.info('team_unfollow', slug: slug)
    return sports_follow_json(slug: slug, kind: 'team', followed: false) if wants_json?
    redirect to(params['return_to'] || '/sports/manage')
  end

  # STUFF #70 — league/tournament follow. Mirrors the team-follow
  # path: ensure the catalog league has a sports_leagues row (lazy
  # upsert via ensure_catalog_league_in_db), then add the follow
  # with kind='league'. The /sports overview's "📅 Tournaments"
  # section reads from this. Articles bridging happens later via
  # SportsEntityArticlesStore (called when the league page renders).
  post '/sports/leagues/follow' do
    slug = params['slug'].to_s
    halt 400, 'slug required' if slug.empty?
    league = SportsLeaguesStore.find_by_slug(slug) || ensure_catalog_league_in_db(slug)
    halt 404, 'league not found' unless league
    SportsFollowsStore.add(user_id: current_user_id, kind: 'league', value: slug)
    AppLogger.info('league_follow', slug: slug, league_id: league['id'])
    return sports_follow_json(slug: slug, kind: 'league', followed: true) if wants_json?
    redirect to(params['return_to'] || '/sports')
  end

  post '/sports/leagues/unfollow' do
    slug = params['slug'].to_s
    halt 400, 'slug required' if slug.empty?
    SportsFollowsStore.remove(user_id: current_user_id, kind: 'league', value: slug)
    AppLogger.info('league_unfollow', slug: slug)
    return sports_follow_json(slug: slug, kind: 'league', followed: false) if wants_json?
    redirect to(params['return_to'] || '/sports')
  end

  # Phase S9 — upcoming-fixtures calendar across followed teams.
  # Same data source for the HTML view and the iCal export so the
  # two stay in sync. Default 30-day window; ?days=N tunable.
  get '/sports/calendar' do
    @page_title = 'Sports calendar'
    days_forward = (params['days'].to_s.match?(/\A\d+\z/) ? params['days'].to_i : 30).clamp(1, 365)
    @days_forward = days_forward

    matches      = SportsMatchesStore.upcoming_for_followed_teams(current_user_id, days_forward: days_forward)
    @matches     = matches
    @teams_by_id = build_teams_by_id_for_matches(matches)
    @leagues_by_id = build_leagues_by_id_for_matches(matches)
    @grouped     = group_by_local_day(matches)
    @ical_url    = url('/sports/calendar.ics')
    erb :sports_calendar
  end

  # iCal export of the same window. Subscribe in Apple/Google
  # Calendar to the URL — refreshes pull every couple of hours.
  # Each VEVENT has UID / DTSTAMP / DTSTART / DTEND / SUMMARY /
  # LOCATION / DESCRIPTION. DTEND uses a per-sport heuristic
  # because matches don't carry a duration on the row.
  get '/sports/calendar.ics' do
    days_forward = (params['days'].to_s.match?(/\A\d+\z/) ? params['days'].to_i : 30).clamp(1, 365)
    matches      = SportsMatchesStore.upcoming_for_followed_teams(current_user_id, days_forward: days_forward)
    teams_by_id  = build_teams_by_id_for_matches(matches)
    leagues_by_id = build_leagues_by_id_for_matches(matches)

    content_type 'text/calendar; charset=utf-8'
    headers      'Content-Disposition' => 'inline; filename="tech-feed-reader-sports.ics"'
    build_ical(matches, teams_by_id, leagues_by_id)
  end

  # League standings page (Phase S8). Renders all groups inside the
  # league (NFC + AFC for NFL, Eastern + Western for NBA/MLS) with
  # the user's followed teams highlighted.
  get '/sports/league/:slug' do |slug|
    @league = SportsLeaguesStore.find_by_slug(slug)
    halt 404, erb(:article_not_found) unless @league

    # STUFF #73 — stamp the Wikipedia title if catalog has one and
    # the row hasn't been seeded yet (catches leagues materialised
    # before the WIKIPEDIA_TITLES map existed).
    if @league['wikipedia_title'].to_s.empty?
      wiki = SportsCatalog.wikipedia_title_for(slug)
      if wiki
        SportsLeaguesStore.set_wikipedia_title!(@league['id'], wiki)
        @league = SportsLeaguesStore.find(@league['id'])
      end
    end
    # Refresh the Wikipedia summary cache (no-op if fresh OR if no
    # title is set). 24h TTL — see Providers::Wikipedia.
    begin
      @league = Providers::Wikipedia.refresh_for_league(@league)
    rescue StandardError => e
      AppLogger.warn('wikipedia_refresh_failed', league: @league['slug'], message: e.message)
    end
    @wikipedia = nil
    if @league['wikipedia_summary'].to_s != ''
      @wikipedia = JSON.parse(@league['wikipedia_summary']) rescue nil
    end

    @page_title  = "#{@league['name']} — Standings"
    rows = SportsStandingsStore.for_league(@league['id'])
    @standings_groups = rows.group_by { |r| r['group_name'] }

    # STUFF #70 follow-up — load matches for the league so the page
    # surfaces fixtures + results, not just the standings table. Pulls
    # whatever sync has populated; tournaments with `source_provider=
    # 'catalog'` (most tennis Slams, golf majors, cycling) stay empty
    # until a provider lands.
    @upcoming_matches = SportsMatchesStore.upcoming_for_league(@league['id'], limit: 20)
    # Tennis tournaments: show all results grouped by round so the full
    # draw is browsable. Other sports keep the 12-match recent window.
    @recent_finals = if @league['sport'] == 'tennis'
                       SportsMatchesStore.finals_by_round_for_league(@league['id'])
                     else
                       SportsMatchesStore.recent_finals_for_league(@league['id'], limit: 12)
                     end
    @results_by_round = @league['sport'] == 'tennis' &&
                        @recent_finals.any? { |m| m['period'].to_s != '' }
    # STUFF #78 — split tennis results into current year vs historical so
    # the ongoing tournament leads and previous editions are secondary.
    if @results_by_round
      this_year = Date.today.year.to_s
      @finals_this_year = @recent_finals.select { |m| m['scheduled_at'].to_s.start_with?(this_year) }
      @finals_historical = @recent_finals.reject { |m| m['scheduled_at'].to_s.start_with?(this_year) }
    end

    # Build a teams_by_id that covers both the standings teams and any
    # team referenced by the new match rows (some matches may involve
    # teams not in the standings — e.g. group-stage opponents who
    # haven't been added to the table yet).
    team_ids  = rows.map { |r| r['team_id'] }
    team_ids += (@upcoming_matches + @recent_finals).flat_map { |m| [m['home_team_id'], m['away_team_id']] }
    team_ids  = team_ids.compact.uniq
    @teams_by_id = team_ids.each_with_object({}) do |tid, h|
      h[tid] = SportsTeamsStore.find(tid)
    end

    # Followed-team highlight: which slug is in sports_follows?
    @followed_slugs = SportsFollowsStore.for_kind(current_user_id, 'team').map { |f| f['value'] }.to_set
    erb :sports_league
  end

  # Per-team detail page. Aggregates every article + podcast episode
  # from the team's catalog feed_urls (intersected with what the
  # user has actually subscribed to). Same vertical-card layout as
  # the /sports overview page so the visual language is consistent.
  get '/sports/team/:slug' do |slug|
    @team = SportsTeams.find(slug)
    # STUFF #67 — fall back to the DB-side sports_teams catalog when
    # the curated Ruby module doesn't know this slug. The module only
    # ships ~5 curated teams (Eagles, Sixers, Union, All Blacks,
    # Tennis); standings tables link every team to /sports/team/<slug>
    # regardless of catalog coverage, so without a fallback every
    # non-curated row 404s (FIFA World Cup countries, most NFL/NBA
    # teams, etc.). The DB path renders a leaner template focused on
    # what we know: header + standings + fixtures + results + mentions.
    if @team.nil?
      db_team = SportsTeamsStore.find_by_slug(slug)
      halt 404, erb(:article_not_found) unless db_team

      @team_row      = db_team
      @league        = SportsLeaguesStore.find(db_team['league_id'])
      @standings     = SportsStandingsStore.for_team(db_team['id'])
      @upcoming      = SportsMatchesStore.upcoming_for_team(db_team['id'], limit: 8)
      @recent_finals = SportsMatchesStore.recent_finals_for_team(db_team['id'], limit: 6)
      @teams_by_id   = SportsTeamsStore.all.each_with_object({}) { |t, h| h[t['id']] = t }
      @followed      = SportsFollowsStore.for_kind(current_user_id, 'team').any? { |f| f['value'] == db_team['slug'] }

      # Cache + FTS5 phrase MATCH on the team's name — same bridge
      # the curated team pages populate.
      SportsEntityArticlesStore.refresh_for(
        kind: 'team', entity_id: db_team['id'], name: db_team['name']
      )
      @mentions = SportsEntityArticlesStore.for_entity(
        kind: 'team', entity_id: db_team['id'], limit: 20
      )

      @page_title = db_team['name']
      halt erb(:sports_team_db)
    end

    @feeds_by_id = FeedsStore.for_user(current_user_id).each_with_object({}) { |f, h| h[f['id']] = f }
    @team_feeds  = SportsTeams.subscribed_feeds_for(@team)
    feed_ids     = @team_feeds.map { |f| f['id'] }

    @articles = feed_ids.flat_map do |fid|
      ArticlesStore.for_feed(current_user_id, fid, limit: 25, state: :all)
    end.sort_by { |a| a['published_at'].to_s }.reverse.first(50)

    @summaries_by_article_id = SummaryStore.find_for_ids(@articles.map { |a| a['id'] })
    # STUFF.md #9 — last game on the per-team page. Look up the
    # team's structured-data row by the SportsTeams (Ruby) module
    # slug, then the most recent final from sports_matches.
    @last_final = lookup_last_final_for_team(@team)
    # S8 — current standings row for the team, drives the league-
    # position line in the page header.
    structured_team = SportsTeamsStore.find_by_slug(@team[:slug])
    @standings = structured_team ? SportsStandingsStore.for_team(structured_team['id']) : nil
    @league    = (@standings && SportsLeaguesStore.find(@standings['league_id'])) ||
                 (structured_team && SportsLeaguesStore.find(structured_team['league_id']))
    # S7 follow-up #2 — articles mentioning the team. Cache + FTS5
    # phrase MATCH on the team's display name. Only enabled when
    # the team has a sports_teams DB row (entity_id is required).
    @related_articles = []
    if structured_team
      SportsEntityArticlesStore.refresh_for(
        kind: 'team', entity_id: structured_team['id'], name: @team[:name]
      )
      @related_articles = SportsEntityArticlesStore.for_entity(
        kind: 'team', entity_id: structured_team['id'], limit: 30
      )
    end
    @page_title  = @team[:name]
    # STUFF #75 — for the tennis curated team page, surface any followed
    # tennis leagues that have synced match data (Roland Garros, etc.)
    # so the user can navigate directly to live tournament fixtures.
    @tennis_tournaments = []
    if @team[:sport] == :tennis
      tennis_follows = SportsFollowsStore.for_kind(current_user_id, 'league').map { |f| f['value'] }
      @tennis_tournaments = tennis_follows.filter_map do |slug|
        row = SportsLeaguesStore.find_by_slug(slug)
        next unless row && row['sport'] == 'tennis'
        match_count = SportsMatchesStore.upcoming_for_league(row['id'], limit: 1).length +
                      SportsMatchesStore.recent_finals_for_league(row['id'], limit: 1).length
        row if match_count > 0
      end
    end
    erb :sports_team
  end

  # Stored digests, newest first. `make digest` (cron) appends to this
  # list; the detail view renders the saved html_body inline.
  get '/digests' do
    @page_title = 'Digests'
    @digests    = DigestStore.recent(current_user_id, limit: 100)
    erb :digests
  end

  get '/digests/:id' do |id|
    @digest = DigestStore.find(current_user_id, id)
    halt 404, 'Digest not found' unless @digest
    @page_title       = @digest['subject']
    @claude_available = Summarizer::Claude.available?
    erb :digest
  end

  # Manual Claude summary of a digest. Cached on the row (one-shot
  # per digest), so a re-visit of /digests/:id never re-spends tokens.
  # Returns a notice when the row already has a summary, surfacing
  # to the user that no API call was made. Inputs come from the
  # digest's stored text_body, which is composed offline by
  # `make digest`, so this route is fast and doesn't need Sidekiq.
  post '/digests/:id/summarize' do |id|
    digest = DigestStore.find(current_user_id, id)
    halt 404 unless digest

    if digest['llm_summary'].to_s.strip != ''
      AppLogger.info('digest_summarize', id: id, status: :cached)
      redirect to("/digests/#{id}?notice=already-summarized")
    end

    guard = LlmGuard.check(user_id: current_user_id)
    if guard.denied?
      AppLogger.warn('llm_denied', route: '/digests/:id/summarize', reason: guard.reason, user_id: current_user_id)
      redirect to("/digests/#{id}?error=llm-quota&msg=#{CGI.escape(guard.message)}")
    end

    result = Summarizer::Claude.summarize_digest(
      subject:   digest['subject'],
      text_body: digest['text_body']
    )
    case result.status
    when :ok
      DigestStore.update_llm_summary(current_user_id, id, summary: result.text, model: result.model)
      LlmUsageStore.record!(user_id: current_user_id, route: '/digests/:id/summarize',
                            model: result.model, input_tokens: result.input_tokens, output_tokens: result.output_tokens)
      AppLogger.info('digest_summarize', id: id, status: :ok, model: result.model)
      redirect to("/digests/#{id}?notice=llm-summarized&model=#{CGI.escape(result.model.to_s)}")
    when :unavailable
      redirect to("/digests/#{id}?error=llm-unavailable")
    when :empty
      redirect to("/digests/#{id}?error=empty-content")
    else
      redirect to("/digests/#{id}?error=llm-failed&msg=#{CGI.escape(result.error.to_s)}")
    end
  end

  # Phase 8 — AI-assisted triage. /triage list view + manual trigger;
  # POST persists into TriageStore + renders the new run inline.
  # /triage/:id surfaces a historical run (cron entries from
  # `make triage` or earlier manual clicks).
  get '/triage' do
    @page_title       = 'Triage'
    @claude_available = Triage::Claude.available?
    @recent_runs      = TriageStore.recent(current_user_id, limit: 20)
    @triage_result    = nil
    @triage_topic     = sanitize_topic_filter(params['topic'])
    erb :triage
  end

  get '/triage/:id' do |id|
    row = TriageStore.find(current_user_id, id)
    halt 404, 'Triage not found' unless row
    @page_title       = "Triage — #{row['generated_at']}"
    @claude_available = Triage::Claude.available?
    @recent_runs      = TriageStore.recent(current_user_id, limit: 20)
    @triage_result    = triage_struct_from_row(row)
    @articles_by_uid  = preload_articles_by_uid(@triage_result)
    @feeds_by_id      = FeedsStore.for_user(current_user_id).each_with_object({}) { |f, h| h[f['id']] = f }
    article_ids = @articles_by_uid.values.map { |a| a['id'] }
    @summaries_by_article_id = SummaryStore.find_for_ids(article_ids)
    @triage_id        = row['id']
    erb :triage
  end

  post '/triage' do
    @page_title       = 'Triage'
    @claude_available = Triage::Claude.available?
    @triage_topic     = sanitize_topic_filter(params['topic'])

    guard = LlmGuard.check(user_id: current_user_id)
    if guard.denied?
      AppLogger.warn('llm_denied', route: '/triage', reason: guard.reason, user_id: current_user_id)
      redirect to("/triage?error=llm-quota&msg=#{CGI.escape(guard.message)}")
    end

    @triage_result    = Triage::Claude.run(current_user_id, topic: @triage_topic)
    if @triage_result.status == :ok && @triage_result.input_tokens
      LlmUsageStore.record!(user_id: current_user_id, route: '/triage',
                            model: @triage_result.model, input_tokens: @triage_result.input_tokens,
                            output_tokens: @triage_result.output_tokens)
    end
    AppLogger.info('triage_manual_trigger',
                   status:        @triage_result.status,
                   topic:         @triage_topic,
                   unread_count:  @triage_result.unread_count,
                   must_read:     @triage_result.must_read.to_a.length,
                   optional:      @triage_result.optional.to_a.length,
                   skip:          @triage_result.skip.to_a.length)
    if @triage_result.status != :unavailable
      @triage_id = TriageStore.create(current_user_id, @triage_result)
      AppLogger.info('triage_stored', id: @triage_id, status: @triage_result.status)
    end
    @recent_runs     = TriageStore.recent(current_user_id, limit: 20)
    @articles_by_uid = preload_articles_by_uid(@triage_result)
    @feeds_by_id     = FeedsStore.for_user(current_user_id).each_with_object({}) { |f, h| h[f['id']] = f }
    # STUFF.md #8 — inline summaries for the triage cards.
    article_ids = @articles_by_uid.values.map { |a| a['id'] }
    @summaries_by_article_id = SummaryStore.find_for_ids(article_ids)
    erb :triage
  end

  # Manual digest trigger — same code path as `make digest` (the cron
  # script), but kicked off from the /digests page button. Composition
  # is fast (one SQL pull + render, ~50ms typical) so we run inline
  # rather than enqueueing to Sidekiq. ?window_hours and ?limit
  # override the defaults if the user wants a longer or wider digest.
  post '/digests' do
    window = (params['window_hours'].to_s.match?(/\A\d+\z/) ? params['window_hours'].to_i : Digests::DEFAULT_WINDOW_HOURS).clamp(1, 720)
    limit  = (params['limit'].to_s.match?(/\A\d+\z/)        ? params['limit'].to_i        : Digests::DEFAULT_LIMIT).clamp(1, 200)
    id, result = Digests.generate_and_store!(current_user_id, window_hours: window, limit: limit)
    AppLogger.info('digest_manual_trigger', id: id, count: result.count, window_hours: window)
    redirect to("/digests/#{id}?notice=generated&count=#{result.count}")
  end

  get '/article/:uid' do |uid|
    @article = ArticlesStore.find_by_uid(uid)
    halt 404, erb(:article_not_found) unless @article

    @feed            = FeedsStore.find(@article['feed_id'])
    @state           = ReadStateStore.opened!(current_user_id, @article['id'])
    @article_tags    = TagsStore.tags_for_article(current_user_id, @article['id'])
    @all_tags        = TagsStore.all(current_user_id)
    @summary         = SummaryStore.find(@article['id'])
    @claude_available = Summarizer::Claude.available?
    @related         = Recommendation.for_article(current_user_id, @article, limit: 5)
    @read_next       = Recommendation::ForYou.next_after(current_user_id, @article) ||
                       @related.find { |a| a['id'] != @article['id'] }
    @feeds_by_id     = FeedsStore.for_user(current_user_id).each_with_object({}) { |f, h| h[f['id']] = f }
    @page_title      = @article['title']
    # Chat context — give the assistant the article body (capped) so
    # it can answer questions about what the user is reading. The
    # widget reads window.PAGE_CONTEXT and posts it to /chat.
    @chat_context    = {
      title:   @article['title'].to_s,
      excerpt: @article['content_text'].to_s
    }
    erb :article
  end

  # Regenerate the extractive summary for an article. The summary is
  # already auto-generated on import, so this is mainly useful when the
  # algorithm changes or content_text has been updated. Runs synchronously
  # — no network — so it returns quickly.
  post '/article/:uid/summarize' do |uid|
    article = ArticlesStore.find_by_uid(uid)
    halt 404 unless article

    summary = Summarizer::Extractive.summarize(article['content_text'].to_s)
    if summary.empty?
      redirect to("/article/#{uid}?error=empty-content")
    else
      SummaryStore.upsert(article['id'], extractive: summary)
      redirect to("/article/#{uid}?notice=resummarized")
    end
  end

  # LLM summary via Claude. Opt-in (only fires when the user clicks
  # "Summarize with Claude"). Cached forever per article id; never
  # auto-invalidated. The button is hidden in the view when
  # Summarizer::Claude.available? is false (no API key set).
  # Chat backend for the floating widget. Stateless on the server —
  # the widget keeps the message thread in localStorage (per page URL)
  # and replays it on every turn. Body is JSON:
  #   { message, history: [{role, content}, ...], context: {url, title, excerpt} }
  # Response shape mirrors Chat::Claude::Result.
  post '/chat' do
    content_type :json

    payload = parse_json_body
    halt 400, { status: 'error', error: 'invalid JSON body' }.to_json unless payload

    guard = LlmGuard.check(user_id: current_user_id)
    if guard.denied?
      AppLogger.warn('llm_denied', route: '/chat', reason: guard.reason, user_id: current_user_id)
      status 429
      return { status: 'denied', reason: guard.reason.to_s, error: guard.message }.to_json
    end

    result = Chat::Claude.respond(
      message: payload['message'].to_s,
      history: payload['history'] || [],
      context: {
        url:     payload.dig('context', 'url').to_s,
        title:   payload.dig('context', 'title').to_s,
        excerpt: payload.dig('context', 'excerpt').to_s
      }
    )

    case result.status
    when :ok
      if result.usage
        LlmUsageStore.record!(user_id: current_user_id, route: '/chat',
                              model: result.model,
                              input_tokens:  result.usage[:input_tokens]  || result.usage['input_tokens'],
                              output_tokens: result.usage[:output_tokens] || result.usage['output_tokens'])
      end
      { status: 'ok', reply: result.text, model: result.model, usage: result.usage }.to_json
    when :unavailable
      status 503
      { status: 'unavailable', error: 'Claude not configured (set CLAUDE_API_KEY in .credentials)' }.to_json
    when :empty
      status 400
      { status: 'empty', error: 'message cannot be empty' }.to_json
    else
      status 500
      { status: 'error', error: result.error.to_s }.to_json
    end
  end

  # Lightweight probe so the widget's bootstrap JS can hide the button
  # entirely when Claude isn't configured.
  get '/chat/health' do
    content_type :json
    { available: Chat::Claude.available?, model: Chat::Claude::MODEL }.to_json
  end

  post '/article/:uid/summarize/llm' do |uid|
    article = ArticlesStore.find_by_uid(uid)
    halt 404 unless article

    guard = LlmGuard.check(user_id: current_user_id)
    if guard.denied?
      AppLogger.warn('llm_denied', route: '/article/:uid/summarize/llm', reason: guard.reason, user_id: current_user_id)
      redirect to("/article/#{uid}?error=llm-quota&msg=#{CGI.escape(guard.message)}")
    end

    result = Summarizer::Claude.summarize(
      title:        article['title'].to_s,
      content_text: article['content_text'].to_s
    )

    case result.status
    when :ok
      SummaryStore.upsert(article['id'], llm: result.text, llm_model: result.model)
      LlmUsageStore.record!(user_id: current_user_id, route: '/article/:uid/summarize/llm',
                            model: result.model, input_tokens: result.input_tokens, output_tokens: result.output_tokens)
      redirect to("/article/#{uid}?notice=llm-summarized&model=#{CGI.escape(result.model)}")
    when :unavailable then redirect to("/article/#{uid}?error=llm-unavailable")
    when :empty       then redirect to("/article/#{uid}?error=empty-content")
    else                   redirect to("/article/#{uid}?error=llm-failed&msg=#{CGI.escape(result.error.to_s)}")
    end
  end

  post '/article/:uid/read' do |uid|
    article = ArticlesStore.find_by_uid(uid)
    halt 404 unless article
    read = params['read'] != '0'  # default true; pass read=0 to mark unread
    ReadStateStore.mark_read(current_user_id, article['id'], read: read)
    redirect to(params['return_to'] || "/article/#{uid}")
  end

  post '/article/:uid/bookmark' do |uid|
    article = ArticlesStore.find_by_uid(uid)
    halt 404 unless article
    value = params['value'] != '0'
    ReadStateStore.mark_bookmarked(current_user_id, article['id'], value: value)
    redirect to(params['return_to'] || "/article/#{uid}")
  end

  post '/article/:uid/archive' do |uid|
    article = ArticlesStore.find_by_uid(uid)
    halt 404 unless article
    value = params['value'] != '0'
    ReadStateStore.mark_archived(current_user_id, article['id'], value: value)
    redirect to(params['return_to'] || "/article/#{uid}")
  end

  # Phase 3 — per-article 👍/👎 valence. Body param `value` ∈ {1, -1, 0}.
  # Toggle behaviour lives at the UI layer (the button form posts the
  # next state — clicking 👍 when already +1 posts 0 to clear).
  post '/article/:uid/feedback' do |uid|
    article = ArticlesStore.find_by_uid(uid)
    halt 404 unless article
    value = case params['value'].to_s
            when '1', '+1' then 1
            when '-1'      then -1
            when '0', ''   then 0
            else                halt 400, 'feedback value must be -1, 0, or +1'
            end
    ReadStateStore.mark_feedback(current_user_id, article['id'], value: value)
    AppLogger.info('article_feedback', uid: uid, value: value)
    if request.env['HTTP_ACCEPT'].to_s.include?('application/json')
      content_type :json
      return { ok: true, value: value }.to_json
    end
    redirect to(params['return_to'] || "/article/#{uid}")
  end

  # Phase 4 — passive listened-percent signal posted by the global
  # player. Accepts JSON `{signal: -1|0|1, listened_pct: 0..1}`. The
  # listened_pct is logged for telemetry but the persisted signal is
  # whatever the player resolved to (≥80% ⇒ +1, <10% with >30s
  # playback ⇒ -1). Explicit feedback (Phase 3) always wins — the
  # store's mark_passive_feedback no-ops if `feedback != 0`.
  #
  # Uses sendBeacon from the player on pagehide, so the response body
  # is best-effort; we still return JSON for the on-ended path which
  # uses fetch().
  post '/api/podcasts/:uid/feedback' do |uid|
    content_type :json
    article = ArticlesStore.find_by_uid(uid)
    halt 404, JSON.generate(error: 'unknown uid') unless article

    body = parse_json_body
    halt 400, JSON.generate(error: 'invalid JSON body') unless body.is_a?(Hash)
    signal = body['signal']
    halt 400, JSON.generate(error: 'signal must be -1, 0, or +1') unless [-1, 0, 1].include?(signal)

    listened_pct = body['listened_pct'].to_f
    explicit_present = ReadStateStore.get(current_user_id, article['id'])['feedback'].to_i != 0
    ReadStateStore.mark_passive_feedback(current_user_id, article['id'], value: signal)

    AppLogger.info('podcast_passive_feedback',
                   uid: uid, signal: signal, listened_pct: listened_pct,
                   explicit_present: explicit_present)

    JSON.generate(ok: true, applied: !explicit_present, explicit_present: explicit_present)
  end

  # Phase 3 — per-feed weighting. Body param `direction` ∈ up | down | reset.
  # Each click bumps by FeedFeedbackStore::STEP (0.25), clamped to
  # [FLOOR, CEILING]. :reset deletes the row.
  post '/feeds/:id/feedback' do |id|
    feed = FeedsStore.find(id.to_i)
    halt 404 unless feed
    direction = params['direction'].to_s.to_sym
    halt 400, 'direction must be up, down, or reset' unless FeedFeedbackStore::DIRECTIONS.include?(direction)
    weight = FeedFeedbackStore.bump(current_user_id, feed['id'], direction: direction)
    AppLogger.info('feed_feedback', feed_id: feed['id'], direction: direction, weight: weight)
    # STUFF #54 — AJAX path used by public/feeds.js weight buttons.
    # Returns the new weight so JS can update the inline display
    # without reloading + scrolling to top.
    if wants_json?
      content_type :json
      return { ok: true, feed_id: feed['id'], direction: direction, weight: weight }.to_json
    end
    redirect to(params['return_to'] || '/feeds')
  end

  # Phase 5 — mute filters. Hard-hide rules; matching articles
  # disappear from /articles and any state_query-backed list, but stay
  # in the DB and remain reachable via /search.
  #
  # POST /mutes        body: kind ∈ {keyword,author,feed}, value (non-empty)
  # POST /mutes/delete body: kind, value
  post '/mutes' do
    kind  = params['kind'].to_s
    value = params['value'].to_s
    halt 400, "kind must be one of #{MuteRulesStore::KINDS.join(', ')}" unless MuteRulesStore::KINDS.include?(kind)
    halt 400, 'value must be non-empty' if value.strip.empty?

    added = MuteRulesStore.add(user_id: current_user_id, kind: kind, value: value)
    AppLogger.info('mute_rule_add', kind: kind, value: value, added: added)
    redirect to(params['return_to'] || "/feeds?notice=#{added ? 'mute-added' : 'mute-duplicate'}&kind=#{kind}&value=#{CGI.escape(value)}")
  end

  post '/mutes/delete' do
    kind  = params['kind'].to_s
    value = params['value'].to_s
    halt 400 unless MuteRulesStore::KINDS.include?(kind)

    removed = MuteRulesStore.remove(user_id: current_user_id, kind: kind, value: value)
    AppLogger.info('mute_rule_remove', kind: kind, value: value, removed: removed)
    redirect to(params['return_to'] || "/feeds?notice=#{removed.positive? ? 'mute-removed' : 'mute-not-found'}")
  end

  # Apply one read-state action to many articles in a single request,
  # so the /articles bulk-toolbar can mark / archive / bookmark a
  # selection in one round-trip instead of N. JSON in, JSON out;
  # returns a per-uid result list so the UI can flag any uids that
  # didn't resolve. Cap is 500 uids per call to keep the SQL bounded.
  BULK_ACTIONS = {
    'read'       => ->(uid, id) { ReadStateStore.mark_read(uid, id,       read:  true)  },
    'unread'     => ->(uid, id) { ReadStateStore.mark_read(uid, id,       read:  false) },
    'bookmark'   => ->(uid, id) { ReadStateStore.mark_bookmarked(uid, id, value: true)  },
    'unbookmark' => ->(uid, id) { ReadStateStore.mark_bookmarked(uid, id, value: false) },
    'archive'    => ->(uid, id) { ReadStateStore.mark_archived(uid, id,   value: true)  },
    'unarchive'  => ->(uid, id) { ReadStateStore.mark_archived(uid, id,   value: false) }
  }.freeze
  BULK_UIDS_MAX = 500

  # Phase 2 polish (2026-05-12) — light JSON lookup for the home-page
  # "Continue listening / watching" tile. The tile is rendered
  # client-side (the watch position lives in localStorage, which the
  # server can't see), so the JS posts the list of uids it found and
  # this returns just enough metadata to render a row: title, feed,
  # the media URLs, and the duration so the tile can show
  # "Resume at M:SS / X:XX". Unknown uids are silently dropped.
  ARTICLE_LOOKUP_MAX_UIDS = 20
  get '/api/articles/lookup' do
    content_type :json
    uids = params['uids'].to_s.split(',').map(&:strip).reject(&:empty?).first(ARTICLE_LOOKUP_MAX_UIDS)
    halt 200, JSON.generate(articles: []) if uids.empty?

    feeds_by_id = FeedsStore.for_user(current_user_id).each_with_object({}) { |f, h| h[f['id']] = f }
    rows = uids.filter_map do |uid|
      article = ArticlesStore.find_by_uid(uid)
      next unless article
      feed = feeds_by_id[article['feed_id']]
      {
        uid:                     article['uid'],
        title:                   article['title'],
        url:                     article['url'],
        audio_url:               article['audio_url'],
        audio_duration_seconds:  article['audio_duration_seconds'],
        feed_title:              feed && (feed['title'] || feed['url']),
        feed_image_url:          feed && feed['image_url']
      }
    end
    JSON.generate(articles: rows)
  end

  post '/api/articles/bulk' do
    content_type :json
    payload = parse_json_body
    halt 400, { status: 'error', error: 'invalid JSON body' }.to_json unless payload

    action = payload['action'].to_s
    handler = BULK_ACTIONS[action]
    unless handler
      halt 400, { status: 'error', error: "unknown action: #{action}",
                  allowed: BULK_ACTIONS.keys }.to_json
    end

    uids = Array(payload['uids']).map(&:to_s).reject(&:empty?).uniq.first(BULK_UIDS_MAX)
    halt 400, { status: 'error', error: 'uids must be a non-empty array' }.to_json if uids.empty?

    applied = 0
    results = uids.map do |uid|
      article = ArticlesStore.find_by_uid(uid)
      if article
        handler.call(current_user_id, article['id'])
        applied += 1
        { uid: uid, ok: true }
      else
        { uid: uid, ok: false, error: 'not_found' }
      end
    end

    AppLogger.info('bulk_apply', action: action, applied: applied, total: uids.length)
    { status: 'ok', action: action, applied: applied, total: uids.length, results: results }.to_json
  end

  TOPICS_WINDOW_OPTIONS = { '7' => 7, '14' => 14, '30' => 30 }.freeze

  # Topic-first reading surface: lists every detected cluster with the
  # most-recent sample articles, in count-desc order. The dashboard
  # widget shows the top 8; this page shows the full set so the user
  # can scan "what's everyone talking about" without per-article
  # scrolling. Each topic chip drills into /topics/:term.
  get '/topics' do
    requested   = params['days'].to_s
    @days       = TOPICS_WINDOW_OPTIONS[requested] || 14
    @topics     = TopicClusters.recent(days: @days, min_articles: 2, limit: 50)
    @page_title = 'Topics'
    erb :topics
  end

  # Topic detail: synthesised "what's happening in <term>" view.
  # Pulls articles matching the term via FTS5, joins their cached
  # extractive summaries (auto-generated at import time), and renders
  # a "Highlights" panel (first sentence of each article's summary)
  # plus the full article list with summaries inline. One round-trip
  # to the DB; no Claude call by default (the summaries are already
  # there from import).
  get '/topics/:term' do |term|
    @term        = term.to_s
    @articles    = ArticlesStore.for_topic(current_user_id, @term, limit: 30)
    @feeds_by_id = FeedsStore.for_user(current_user_id).each_with_object({}) { |f, h| h[f['id']] = f }
    @page_title  = "Topic: #{@term}"

    @highlights = @articles.filter_map do |article|
      summary = article['summary'].to_s.strip
      next if summary.empty?
      first_sentence = summary.split(/(?<=[.!?])\s+/).first
      [first_sentence&.strip, article] if first_sentence && !first_sentence.strip.empty?
    end.first(10)

    erb :topic
  end

  get '/feeds' do
    @page_title  = 'Feeds'
    @feeds       = FeedsStore.for_user(current_user_id)
    @notice      = params['notice']
    @error       = params['error']
    @catalog     = FeedCatalog.by_category
    @subscribed  = @feeds.map { |f| f['url'] }.to_set
    @categories  = FeedCatalog::CATEGORIES
    @feed_weights = FeedFeedbackStore.weights_by_feed_id(current_user_id, @feeds.map { |f| f['id'] })
    @mute_rules = MuteRulesStore.all(current_user_id).group_by { |r| r['kind'] }
    # Phase 4 follow-up (2026-05-12) — "Recommended for you" callout.
    # Scores unsubscribed catalog entries against the user's current
    # subscriptions (cat × 2 + topic). Empty cold-start; otherwise
    # 6 strongest matches surface above the full browse list.
    @recommended = FeedCatalog.recommend_for(subscribed_urls: @subscribed, limit: 6)
    @ai_recommend_available = FeedRecommender::Claude.available?
    @popular_by_type = FeedsStore::POPULAR_TYPES.to_h { |t| [t, FeedsStore.popular_by_type(t)] }
    erb :feeds
  end

  # STUFF.md #23 — AI-assisted feed recommender. Takes a free-text
  # `prompt` form field, runs FeedRecommender::Claude against the
  # curated catalog minus what the user already subscribes to, and
  # re-renders /feeds with the result rendered in a dedicated section.
  # Reuses the existing /feeds view so navigation stays in one place.
  post '/feeds/ai-recommend' do
    @page_title  = 'Feeds'
    @ai_prompt   = params['prompt'].to_s.strip
    @feeds       = FeedsStore.for_user(current_user_id)
    @notice      = params['notice']
    @error       = params['error']
    @catalog     = FeedCatalog.by_category
    @subscribed  = @feeds.map { |f| f['url'] }.to_set
    @categories  = FeedCatalog::CATEGORIES
    @feed_weights = FeedFeedbackStore.weights_by_feed_id(current_user_id, @feeds.map { |f| f['id'] })
    @mute_rules = MuteRulesStore.all(current_user_id).group_by { |r| r['kind'] }
    @recommended = FeedCatalog.recommend_for(subscribed_urls: @subscribed, limit: 6)
    @ai_recommend_available = FeedRecommender::Claude.available?
    @ai_recommend_result = FeedRecommender::Claude.recommend(current_user_id, prompt: @ai_prompt)
    @popular_by_type = FeedsStore::POPULAR_TYPES.to_h { |t| [t, FeedsStore.popular_by_type(t)] }
    erb :feeds
  end

  # One-click add from the curated catalog. Looks the URL up in the
  # catalog (so a user can't grease through with arbitrary metadata via
  # the form), then routes through FeedsStore.add. Idempotent — duplicate
  # URLs short-circuit to a friendly notice.
  post '/feeds/catalog/add' do
    url   = params['url'].to_s.strip
    entry = FeedCatalog.find_by_url(url)
    redirect to('/feeds?error=not-in-catalog') unless entry

    _feed, inserted = FeedsStore.add_for_user(
      user_id: current_user_id,
      url: entry[:url], title: entry[:title],
      fetch_interval_seconds: entry[:interval],
      topic: FeedCatalog.topic_for(entry).to_s
    )
    if inserted
      redirect to("/feeds?notice=catalog-added&title=#{CGI.escape(entry[:title])}")
    else
      redirect to("/feeds?notice=already-subscribed&title=#{CGI.escape(entry[:title])}")
    end
  end

  # Add a feed. URL is required; title and fetch_interval_seconds are
  # optional — once FeedFetcher lands (TODO-004), the title gets backfilled
  # on first successful poll. Until then, the user-supplied title (or the
  # URL itself) is what shows in the list.
  post '/feeds' do
    url = params['url'].to_s.strip

    unless url.match?(%r{\Ahttps?://\S+\z})
      redirect to('/feeds?error=invalid-url')
    end

    title    = (params['title'] || '').strip
    title    = nil if title.empty?
    interval = params['fetch_interval_seconds'].to_i
    interval = FeedsStore::PUBLISHER_INTERVAL if interval <= 0

    # Apple Podcasts URLs (podcasts.apple.com/.../id<digits>) are HTML
    # landing pages, not RSS — the feed parser would silently import
    # zero entries. Resolve to the real feedUrl via iTunes Lookup
    # before insert. On failure (deleted show, network error) we keep
    # the original URL + redirect with a hint so the user knows why
    # it didn't auto-resolve.
    notice = 'added'
    if (apple_id = Providers::ITunesLookup.apple_podcast_id_from_url(url))
      result = Providers::ITunesLookup.lookup_by_id(apple_id)
      case result.status
      when :ok
        url     = result.feed_url
        title ||= result.collection_name
        notice  = 'apple-resolved'
      when :not_found
        redirect to('/feeds?error=apple-not-found')
      when :error
        redirect to('/feeds?error=apple-lookup-failed')
      end
    end

    _feed, inserted = FeedsStore.add_for_user(
      user_id: current_user_id,
      url: url, title: title, fetch_interval_seconds: interval
    )
    if inserted
      redirect to("/feeds?notice=#{notice}")
    else
      redirect to('/feeds?error=duplicate-url')
    end
  end

  # POST-for-delete because plain HTML forms only support GET / POST.
  # A2: this is now an unsubscribe — the catalog feed row stays so other
  # users keep their subscriptions and the fetcher's de-dup still works.
  post '/feeds/:id/delete' do |id|
    if FeedsStore.unsubscribe(current_user_id, id.to_i)
      redirect to('/feeds?notice=removed')
    else
      redirect to('/feeds?error=not-found')
    end
  end

  # ---- JSON API (AJAX endpoints for the feeds page) ------------------
  #
  # These endpoints back the in-page add / remove / refresh interactions
  # so the user keeps their scroll position. The HTML form-target routes
  # above stay in place as a no-JS fallback. JSON shape on success:
  #   { ok: true, feed: {...}, row_html: "<tr>...</tr>" }
  # On error:
  #   { ok: false, error: "duplicate-url", message: "..." }   (HTTP 422)
  #   { ok: false, error: "not-found",     message: "..." }   (HTTP 404)
  #
  # `row_html` reuses views/_feed_row.erb so JS-inserted rows match the
  # server-rendered ones byte-for-byte.

  post '/api/feeds' do
    content_type :json
    url = params['url'].to_s.strip

    unless url.match?(%r{\Ahttps?://\S+\z})
      status 422
      next({ ok: false, error: 'invalid-url', message: "That doesn't look like a valid http(s) URL." }.to_json)
    end

    title    = (params['title'] || '').strip
    title    = nil if title.empty?
    interval = params['fetch_interval_seconds'].to_i
    interval = FeedsStore::PUBLISHER_INTERVAL if interval <= 0

    feed, inserted = FeedsStore.add_for_user(
      user_id: current_user_id,
      url: url, title: title, fetch_interval_seconds: interval
    )
    if inserted
      status 201
      { ok: true, feed: feed, row_html: render_feed_row(feed) }.to_json
    else
      status 422
      { ok: false, error: 'duplicate-url', message: 'That feed is already subscribed.' }.to_json
    end
  end

  delete '/api/feeds/:id' do |id|
    content_type :json
    if FeedsStore.unsubscribe(current_user_id, id.to_i)
      { ok: true, id: id.to_i }.to_json
    else
      status 404
      { ok: false, error: 'not-found', message: 'No feed with that id.' }.to_json
    end
  end

  post '/api/feeds/catalog/add' do
    content_type :json
    url   = params['url'].to_s.strip
    entry = FeedCatalog.find_by_url(url)

    unless entry
      status 422
      next({ ok: false, error: 'not-in-catalog', message: "That URL isn't in the curated catalog." }.to_json)
    end

    feed, inserted = FeedsStore.add_for_user(
      user_id: current_user_id,
      url: entry[:url], title: entry[:title],
      fetch_interval_seconds: entry[:interval],
      topic: FeedCatalog.topic_for(entry).to_s
    )
    if inserted
      status 201
      { ok: true, status: 'added', feed: feed, row_html: render_feed_row(feed) }.to_json
    else
      { ok: true, status: 'already-subscribed', feed: feed, row_html: render_feed_row(feed) }.to_json
    end
  end

  # Refresh-feed endpoints. Not admin: the header "refresh" button +
  # the per-feed buttons on /feeds are user-facing (any signed-in
  # user can enqueue a fetch). Previously lived under /api/admin/*
  # but that was historical naming — STUFF #49's fail-closed admin
  # gate then locked normal users out. Moved to /api/refresh/* so
  # only the WebAuthn sign-in wall applies.
  post '/api/refresh/all' do
    content_type :json
    feeds = FeedsStore.all
    feeds.each { |f| FeedRefreshWorker.perform_async(f['id']) }
    AppLogger.info('refresh_all_enqueued', count: feeds.length, source: 'api')
    { ok: true, queued: feeds.length }.to_json
  end

  post '/api/refresh/:feed_id' do |feed_id|
    content_type :json
    feed = FeedsStore.find(feed_id.to_i)
    unless feed
      status 404
      next({ ok: false, error: 'not-found', message: 'No feed with that id.' }.to_json)
    end

    FeedRefreshWorker.perform_async(feed['id'])
    AppLogger.info('refresh_one_enqueued', feed_id: feed['id'], title: feed['title'], source: 'api')
    { ok: true, feed_id: feed['id'] }.to_json
  end

  # Bulk import via OPML. Skips URLs already present so re-importing the
  # same file is idempotent; flashes a count summary on the redirect.
  post '/feeds/import' do
    upload = params['file']
    redirect to('/feeds?error=missing-file') unless upload && upload[:tempfile]

    begin
      content = upload[:tempfile].read
      entries = OPML.parse(content)
      added   = 0
      skipped = 0
      entries.each do |entry|
        _feed, inserted = FeedsStore.add_for_user(
          user_id: current_user_id,
          url: entry[:url], title: entry[:title]
        )
        inserted ? added += 1 : skipped += 1
      end
      redirect to("/feeds?notice=imported&added=#{added}&skipped=#{skipped}&total=#{entries.length}")
    rescue StandardError => e
      redirect to("/feeds?error=import-failed&msg=#{CGI.escape(e.message)}")
    end
  end

  # Export the user's subscribed feeds as OPML 2.0.
  get '/feeds/export.opml' do
    content_type 'text/x-opml'
    attachment "tech-feed-reader-feeds-#{Date.today}.opml"
    OPML.build(FeedsStore.for_user(current_user_id))
  end

  get '/tags' do
    @page_title     = 'Tags'
    @tags           = TagsStore.all(current_user_id)
    @article_counts = TagsStore.article_counts(current_user_id)
    @feeds_by_id    = FeedsStore.for_user(current_user_id).each_with_object({}) { |f, h| h[f['id']] = f }
    @notice         = params['notice']
    @error          = params['error']
    erb :tags
  end

  # Add a new tag rule. Auto-runs the backfill applier so existing
  # articles get tagged immediately, not just future fetches.
  post '/tags' do
    name = params['name'].to_s.strip
    kind = params['match_kind'].to_s.strip
    val  = params['match_value'].to_s.strip

    redirect to('/tags?error=missing-fields') if name.empty? || val.empty?
    redirect to('/tags?error=invalid-kind')   unless TagsStore::KINDS.include?(kind)

    if kind == 'regex'
      begin
        Regexp.new(val)
      rescue RegexpError
        redirect to('/tags?error=invalid-regex')
      end
    end

    begin
      tag    = TagsStore.add(user_id: current_user_id, name: name, match_kind: kind, match_value: val)
      tagged = TagsApplier.apply_to_existing(tag)
      redirect to("/tags?notice=added&tagged=#{tagged}")
    rescue PG::UniqueViolation
      # UNIQUE(user_id, name) index. UniqueViolation descends from
      # PG::IntegrityConstraintViolation but we name it explicitly here
      # to avoid swallowing unrelated PG errors.
      redirect to('/tags?error=duplicate-name')
    end
  end

  post '/tags/:id/delete' do |id|
    if TagsStore.remove(current_user_id, id.to_i)
      redirect to('/tags?notice=removed')
    else
      redirect to('/tags?error=not-found')
    end
  end

  # Toggle a tag on a single article. value=add | remove (default add).
  # Used by the manual-override chips on /article/:uid.
  post '/article/:uid/tag/:tag_id' do |uid, tag_id|
    article = ArticlesStore.find_by_uid(uid)
    halt 404 unless article
    halt 404 unless TagsStore.find(current_user_id, tag_id.to_i)

    if params['value'] == 'remove'
      TagsStore.untag_article(article['id'], tag_id.to_i)
    else
      TagsStore.tag_article(article['id'], tag_id.to_i)
    end
    redirect to(params['return_to'] || "/article/#{uid}")
  end

  get '/search' do
    @query    = params['q'].to_s.strip
    @page     = [params['page'].to_i, 1].max
    @per_page = 50
    offset    = (@page - 1) * @per_page

    if @query.empty?
      @results = []
      @error   = nil
    else
      begin
        @results = ArticlesStore.search(current_user_id, @query, limit: @per_page, offset: offset)
        @error   = nil
      rescue PG::Error => e
        @results = []
        @error   = e.message
      end
    end

    @feeds_by_id     = FeedsStore.for_user(current_user_id).each_with_object({}) { |f, h| h[f['id']] = f }
    @tags_by_article = TagsStore.tags_for_articles(current_user_id, @results.map { |a| a['id'] })
    @page_title      = @query.empty? ? 'Search' : "Search: #{@query}"
    erb :search
  end

  # Pre-launch — operator status page. Stitches /health + Sidekiq
  # stats + sidekiq-cron job state + corpus counts into one
  # at-a-glance view. Same Basic Auth + WebAuthn gate as the rest
  # of /admin/*.
  get '/admin/status' do
    @page_title = 'Status'
    @now        = Time.now.utc

    # Reuse the /health JSON computation. Mirror the route's logic
    # rather than re-implement.
    db_status   = check_db
    redis_check = check_redis
    sidekiq_h   = check_sidekiq
    overall     =
      if db_status[:status] != 'ok' then 'fail'
      elsif redis_check[:status] != 'ok' then 'degraded'
      else 'ok'
      end
    @health = {
      status: overall,
      checks: { db: db_status, redis: redis_check, sidekiq: sidekiq_h }
    }

    # Uptime in a human-readable form.
    sec  = AppVersion.uptime_seconds.to_i
    days = sec / 86_400
    hrs  = (sec % 86_400) / 3600
    mins = (sec % 3600) / 60
    @uptime_human = [
      days.positive? ? "#{days}d" : nil,
      hrs.positive?  ? "#{hrs}h"  : nil,
      "#{mins}m"
    ].compact.join(' ')

    @sidekiq = sidekiq_stats
    @db_size_pretty = Database.connection.execute(
      "SELECT pg_size_pretty(pg_database_size(current_database())) AS s"
    ).first['s'] rescue 'unknown'

    # sidekiq-cron job state from Redis. The require is defensive —
    # the worker process loads it at boot, but the web process only
    # touches it here. Safe to re-require; gem load is idempotent.
    begin
      require 'sidekiq-cron'
      @cron_jobs = Sidekiq::Cron::Job.all.map do |j|
        {
          name:              j.name,
          klass:             j.klass,
          cron:              j.cron,
          last_enqueue_time: j.last_enqueue_time
        }
      end.sort_by { |j| j[:cron] }
    rescue StandardError
      @cron_jobs = []
    end

    articles_last_24h =
      begin
        Database.connection.execute(
          "SELECT COUNT(*) AS c FROM articles WHERE created_at > NOW() - INTERVAL '24 hours'"
        ).first['c'].to_i
      rescue StandardError
        0
      end
    @counts = {
      users:              UsersStore.count,
      feeds:              FeedsStore.count,
      articles:           ArticlesStore.count,
      articles_last_24h:  articles_last_24h,
      support_new:        SupportMessagesStore.count_by_status['new'] || 0
    }

    erb :admin_status
  end

  # STUFF #62 — admin queue for the public /contact form. Gated by
  # the existing /admin/* Basic Auth wall (#49) + WebAuthn sign-in.
  # Newest-first; filter by status via ?status=new|reviewed|responded.
  get '/admin/support' do
    @page_title = 'Support messages'
    @status     = params['status'].to_s
    @status     = nil unless SupportMessagesStore::STATUSES.include?(@status)
    @messages   = SupportMessagesStore.list(status: @status)
    @counts     = SupportMessagesStore.count_by_status
    user_ids    = @messages.map { |m| m['user_id'] }.compact.uniq
    @users_by_id = user_ids.each_with_object({}) { |uid, h| h[uid] = UsersStore.find(uid) }
    erb :admin_support
  end

  post '/admin/support/:id/update' do |id|
    msg = SupportMessagesStore.find(id)
    halt 404 unless msg
    SupportMessagesStore.update!(
      id,
      status:     params['status'],
      admin_note: params['admin_note'].to_s[0, SupportMessagesStore::ADMIN_NOTE_MAX]
    )
    AppLogger.info('support_message_updated', id: id, status: params['status'])
    redirect to('/admin/support')
  end

  # System overview — single page consolidating counts, DB size,
  # HealthRegistry digest, scheduler "due now", and integration
  # presence. Admin sub-pages (cache, health, future sidekiq) are
  # listed at the bottom for navigation.
  get '/admin' do
    @page_title = 'Admin'

    db = Database.connection
    @counts = {
      feeds:         FeedsStore.count,
      articles:      ArticlesStore.count,
      unread:        ReadStateStore.unread_count(current_user_id),
      bookmarked:    ReadStateStore.bookmarked_count(current_user_id),
      tags:          TagsStore.count(current_user_id),
      article_tags:  db.execute('SELECT COUNT(*) AS c FROM article_tags').first['c'],
      summaries:     db.execute('SELECT COUNT(*) AS c FROM summaries').first['c'],
      summaries_llm: db.execute("SELECT COUNT(*) AS c FROM summaries WHERE llm IS NOT NULL AND llm != ''").first['c']
    }

    # Managed-PG size: pg_database_size returns bytes for the current DB.
    @db_bytes = db.execute('SELECT pg_database_size(current_database()) AS b').first['b'].to_i

    @degraded            = HealthRegistry.degraded?
    @health_enabled      = HealthRegistry.enabled?
    @health_observations = HealthRegistry.observations.length

    @tracing_enabled = Tracing.enabled?
    @tracing_otlp    = Tracing.otlp_enabled?
    @tracing_endpoint = Tracing.endpoint
    @tracing_spans   = Tracing::Recorder.count

    @due_now          = Scheduler.due_feeds(FeedsStore.all).length
    @claude_available = Summarizer::Claude.available?

    # Sidekiq stats — wrapped so a Redis outage shows the worker as
    # offline rather than 500ing the whole admin page.
    @sidekiq = sidekiq_stats

    erb :admin
  end

  # STUFF #49 follow-up — admin logout / re-login. Basic Auth has no
  # native logout; the browser caches credentials per-origin until the
  # user closes the tab or clears them manually. We work around that
  # with a session flag: `session[:admin_logged_out] = true` makes the
  # before-filter ignore otherwise-valid credentials. `/admin/login`
  # clears the flag (and is exempt from the gate so a logged-out user
  # can actually reach it).
  post '/admin/logout' do
    session[:admin_logged_out] = true
    AppLogger.info('admin_logged_out',
                   user_id: signed_in? ? current_user_id : nil)
    redirect to('/admin')
  end

  get '/admin/login' do
    # session.delete (vs `= false`) — explicit "no key" leaves no
    # ambiguity between "flag intentionally false" and "flag never set."
    session.delete(:admin_logged_out)
    # Cached Basic Auth creds (if any) authenticate the next /admin
    # hit transparently. If the browser has no cached creds, the gate
    # will re-prompt via WWW-Authenticate.
    redirect to('/admin')
  end

  get '/admin/health' do
    @page_title    = 'Provider health'
    @observations  = HealthRegistry.observations.last(50).reverse
    @summary       = HealthRegistry.per_feed_summary
    @degraded      = HealthRegistry.degraded?
    @feeds_by_id   = FeedsStore.all.each_with_object({}) { |f, h| h[f['id']] = f }
    @enabled       = HealthRegistry.enabled?
    erb :admin_health
  end

  # In-memory trace browser. Reads from the process-local
  # Tracing::Recorder ring buffer (size TRACING_RECORDER_CAPACITY,
  # default 200 finished spans). Spans are grouped into traces by
  # hex_trace_id and sorted newest trace first; within a trace, spans
  # render in start-time order so the parent-child structure is
  # readable. ?trace=<hex_trace_id> filters down to one trace.
  get '/admin/traces' do
    @page_title    = 'Traces'
    @enabled       = Tracing.enabled?
    @otlp_enabled  = Tracing.otlp_enabled?
    @endpoint      = Tracing.endpoint
    @service_name  = Tracing.service_name
    @capacity      = Tracing::Recorder.capacity
    @count         = Tracing::Recorder.count

    spans = Tracing::Recorder.spans
    grouped = spans.group_by { |s| s.hex_trace_id }
    @traces = grouped.map do |trace_id, trace_spans|
      ordered  = trace_spans.sort_by(&:start_timestamp)
      start_ns = ordered.first.start_timestamp
      end_ns   = ordered.map(&:end_timestamp).max
      {
        trace_id:    trace_id,
        spans:       ordered,
        start_time:  Time.at(start_ns / 1_000_000_000.0).utc,
        duration_ms: ((end_ns - start_ns) / 1_000_000.0).round(2),
        root_name:   (ordered.find { |s| s.parent_span_id == OpenTelemetry::Trace::INVALID_SPAN_ID } || ordered.first).name
      }
    end.sort_by { |t| -t[:start_time].to_f }

    @focus_trace_id = params['trace'].to_s
    if !@focus_trace_id.empty?
      @traces = @traces.select { |t| t[:trace_id] == @focus_trace_id }
    end

    erb :admin_traces
  end

  # LLM rate-limit dashboard. Shows the active env-driven budgets
  # (feature flag, per-user daily tokens, global hourly tokens/cost)
  # alongside actual usage in the last hour + 24h per user. Read-only;
  # quotas are controlled by env vars set on the host.
  get '/admin/llm-quota' do
    @page_title = 'LLM quota'
    @enabled            = LlmGuard.enabled?
    @user_daily_budget  = LlmGuard.user_daily_token_budget
    @global_hour_tokens = LlmGuard.global_hourly_token_budget
    @global_hour_cost   = LlmGuard.global_hourly_cost_budget
    @tokens_last_hour   = LlmUsageStore.tokens_last_hour_global
    @cost_last_hour     = LlmUsageStore.cost_last_hour_global
    @usage_by_user      = LlmUsageStore.usage_last_24h_by_user
    erb :admin_llm_quota
  end

  # Claude Code token usage + cost + this-repo productivity (commits,
  # lines, PRs merged). Re-parses ~/.claude/projects/**/*.jsonl on
  # every load, plus shells out to git + gh. See app/dev_stats.rb.
  get '/admin/dev-stats' do
    @page_title = 'Dev stats'
    @report     = DevStats.report
    erb :admin_dev_stats
  end

  get '/admin/cache' do
    @page_title  = 'Cache admin'
    @feeds       = FeedsStore.all
    @article_counts = Database.connection
      .execute('SELECT feed_id, COUNT(*) AS c FROM articles GROUP BY feed_id')
      .each_with_object({}) { |row, h| h[row['feed_id']] = row['c'] }
    erb :admin_cache
  end

  # STUFF #48.1 — admin usage analytics. New-users-per-day + total
  # pageviews + per-section breakdown over the last 14 days.
  # Opportunistically prunes pageviews > 90 days on every visit — no
  # recurring-job runner needed; admin browsing is the natural
  # trigger.
  get '/admin/analytics' do
    @page_title = 'Analytics'
    @days       = (params['days'].to_s.match?(/\A\d+\z/) ? params['days'].to_i : 14).clamp(1, 90)

    # Retention sweep (90d). Cheap; logs the count for visibility.
    pruned = PageviewsStore.prune_older_than!(days: 90)
    AppLogger.info('pageviews_prune', deleted: pruned) if pruned.positive?

    @total_users        = UsersStore.count
    @new_users_per_day  = UsersStore.new_users_per_day(days: @days)
    @new_users_total    = @new_users_per_day.sum { |r| r['count'] }

    @pageviews_total   = PageviewsStore.total(days: @days)
    @pageviews_per_day = PageviewsStore.daily_totals(days: @days)
    @section_totals    = PageviewsStore.section_totals(days: @days)

    # Zero-fill the day windows so the chart renders a continuous
    # axis even when some days had no traffic. Both windows share
    # the same date range so the bars line up under the sparkline.
    @day_window = (0...@days).map { |i| (Time.now.utc.to_date - (@days - 1 - i)).iso8601 }
    align = ->(rows) {
      by_day = rows.each_with_object({}) { |r, h| h[r['day']] = r['count'] }
      @day_window.map { |d| by_day[d] || 0 }
    }
    @pageviews_series = align.call(@pageviews_per_day)
    @new_users_series = align.call(@new_users_per_day)

    erb :admin_analytics
  end

  # STUFF #48.1 — admin user-list subpage. Drills into the
  # "new users" count on /admin/analytics. Each row carries
  # passkey-count + recovery-code-count via the dedicated stores
  # (N+1 across users — fine at single-digit user counts; bake a
  # LEFT JOIN COUNT(...) query when this grows past ~100 users).
  get '/admin/users' do
    @page_title = 'Users'
    @users      = UsersStore.all
    @decorated  = @users.map do |u|
      u.merge(
        'passkey_count'    => WebauthnCredentialsStore.count_for_user(u['id']),
        'recovery_unused'  => RecoveryCodesStore.unconsumed_count_for(u['id'])
      )
    end
    erb :admin_users
  end

  # Page-background pool admin: shows the Picsum IDs that
  # public/page-background.js currently rotates through, with author
  # attribution + a link to refresh the pool against Picsum's
  # /v2/list endpoint. Empty pool falls back to a curated default
  # baked into BackgroundPool::DEFAULT_IDS.
  get '/admin/backgrounds' do
    @page_title       = 'Background pool'
    @entries          = BackgroundPool.entries
    @default_ids      = BackgroundPool::DEFAULT_IDS
    @using_default    = @entries.empty?
    @target_pool_size = BackgroundPool::POOL_TARGET_SIZE
    erb :admin_backgrounds
  end

  post '/admin/backgrounds/refresh' do
    inserted = BackgroundPool.refresh!
    redirect to("/admin/backgrounds?notice=refreshed&count=#{inserted}")
  rescue BackgroundPool::RefreshError => e
    AppLogger.warn('background_pool_refresh_failed', error: e.message)
    redirect to("/admin/backgrounds?error=refresh-failed&msg=#{CGI.escape(e.message)}")
  end

  # HTML form-submit refresh endpoints (non-JS fallbacks for the
  # header button + /feeds page). Not admin — see comment on the
  # /api/refresh/* pair above.
  #
  # NOTE: /all must be declared before the :feed_id variant so Sinatra
  # matches the static path first. Otherwise the URL string "all" gets
  # parsed as a feed_id (= 0) and the request 404s.
  post '/refresh/all' do
    feeds = FeedsStore.all
    feeds.each { |f| FeedRefreshWorker.perform_async(f['id']) }
    AppLogger.info('refresh_all_enqueued', count: feeds.length)
    redirect to("/feeds?notice=queued-all&count=#{feeds.length}")
  end

  post '/refresh/:feed_id' do |feed_id|
    feed = FeedsStore.find(feed_id.to_i)
    redirect to('/feeds?error=not-found') unless feed

    FeedRefreshWorker.perform_async(feed['id'])
    AppLogger.info('refresh_one_enqueued', feed_id: feed['id'], title: feed['title'])
    redirect to("/feeds?notice=queued&feed_id=#{feed['id']}")
  end

  # ---- Boot -----------------------------------------------------------
end

# Compose the runtime Rack app: Sinatra at the root + Sidekiq::Web
# mounted at /admin/sidekiq. Sidekiq::Web is itself a Rack app that
# expects a session for CSRF on its POST actions (retry / kill jobs);
# we wire a cookie session scoped to its mount point so the main app's
# routes stay session-free.
#
# STUFF #51 — Sidekiq::Web mounts BEFORE Sinatra in this Rack::Builder
# chain, so the Sinatra-level admin Basic Auth gate from #49 never
# sees these requests. Wrap Sidekiq::Web with Rack::Auth::Basic
# using the same ADMIN_USERNAME / ADMIN_PASSWORD credentials, fail-
# closed (admin_credentials returns nil if either env var is unset
# or empty → block returns nil → Rack::Auth::Basic 401s).
#
# In test env we never start the server (rspec uses Rack::Test against
# TechFeedReader directly), so this whole block is gated on direct
# script invocation.
if __FILE__ == $PROGRAM_NAME
  require 'sidekiq/web'
  require 'sidekiq/cron/web'   # adds the "Cron" tab to /admin/sidekiq
  require 'rack/session/cookie'
  require 'rack/auth/basic'
  require 'securerandom'
  require 'rackup/handler'

  Sidekiq::Web.use Rack::Session::Cookie,
                   secret:    ENV['SIDEKIQ_WEB_SECRET'] || SecureRandom.hex(32),
                   same_site: :lax
  Sidekiq::Web.use Rack::Auth::Basic, 'Sidekiq' do |user, pass|
    expected = Auth.admin_credentials
    expected &&
      Rack::Utils.secure_compare(expected[0], user.to_s) &&
      Rack::Utils.secure_compare(expected[1], pass.to_s)
  end

  combined = Rack::Builder.app do
    map '/admin/sidekiq' do
      run Sidekiq::Web
    end
    map '/' do
      use RequestLogMiddleware::App
      use MetricsMiddleware
      use RateLimiter
      run TechFeedReader.new
    end
  end

  host = ENV['RACK_ENV'] == 'production' ? '0.0.0.0' : 'localhost'
  Rackup::Handler.get('puma').run(combined, Port: 4567, Host: host)
end
