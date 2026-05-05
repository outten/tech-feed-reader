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
require_relative 'opml'
require_relative 'recommendation'
require_relative 'topic_clusters'
require_relative 'feed_catalog'
require_relative 'version'
require_relative 'tracing'
require_relative 'metrics'
require_relative 'metrics_middleware'

# Sidekiq client config + the worker class. Loading the config only
# registers Sidekiq.configure_client/server blocks — no Redis
# connection happens until the first perform_async, so this is safe to
# require in test (specs stub perform_async).
require_relative 'sidekiq_config'
require_relative 'workers/feed_refresh_worker'
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

  # Surface the real exception in test runs so a 500 in rack-test prints
  # the underlying error class + backtrace instead of the bare "Internal
  # Server Error" page. Has no effect outside test env.
  configure :test do
    set :raise_errors, true
    set :dump_errors, false
    set :show_exceptions, false
  end

  # ---- Request logging ------------------------------------------------
  # Every HTTP request logs a single JSON line to STDOUT with
  # method / path / status / latency. Errors get a separate event
  # before being re-raised. See app/logger.rb for the format.

  before do
    @request_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  after do
    next if @request_started_at.nil?
    ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @request_started_at) * 1000).round
    AppLogger.info(
      'http_request',
      method:     request.request_method,
      path:       request.path_info,
      query:      request.query_string.empty? ? nil : request.query_string,
      status:     response.status,
      latency_ms: ms
    )
  end

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
  end

  helpers do
    # Cache-bust query string for static assets — same pattern as t-money so
    # CSS/JS edits show up on next render without a hard reload.
    def asset_mtime(rel_path)
      full = File.join(settings.root, rel_path)
      File.exist?(full) ? File.mtime(full).to_i : Time.now.to_i
    end

    # Used in feed-fetch UI; ISO8601 timestamps become "2 minutes ago".
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
      erb :_feed_row, locals: { feed: feed }, layout: false
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
      version:        AppVersion::GIT_SHA,
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

  get '/' do
    redirect '/dashboard'
  end

  get '/dashboard' do
    @page_title       = 'Dashboard'
    @articles         = ArticlesStore.recent(limit: 20, state: :unread)
    @feeds_by_id      = FeedsStore.all.each_with_object({}) { |f, h| h[f['id']] = f }
    @article_count    = ArticlesStore.count
    @unread_count     = ReadStateStore.unread_count
    @bookmark_count   = ReadStateStore.bookmarked_count
    @feed_count       = FeedsStore.count
    @degraded         = HealthRegistry.degraded?
    @daily_counts     = ArticlesStore.daily_counts(days: 30)
    @top_feeds        = ArticlesStore.counts_by_feed(limit: 10)
    @top_tags_week    = TagsStore.top_in_window(days: 7, limit: 8)
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
    @tag_filter  = tag_id.positive?  ? TagsStore.find(tag_id)   : nil

    @state_filter = (params['state'] || 'all').to_sym
    @state_filter = :all unless ARTICLES_STATE_FILTERS.include?(@state_filter)

    @kind_filter = params['kind'].to_s == 'podcast' ? :podcast : :all

    @articles = if @tag_filter
                  ArticlesStore.for_tag(tag_id, limit: @per_page, offset: offset, state: @state_filter)
                elsif @feed_filter
                  ArticlesStore.for_feed(feed_id, limit: @per_page, offset: offset, state: @state_filter)
                else
                  ArticlesStore.recent(limit: @per_page, offset: offset, state: @state_filter, kind: @kind_filter)
                end

    @feeds_by_id     = FeedsStore.all.each_with_object({}) { |f, h| h[f['id']] = f }
    @tags_by_article = TagsStore.tags_for_articles(@articles.map { |a| a['id'] })
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
      limit:                BUS_LIMIT,
      kind:                 :podcast,
      max_duration_seconds: @cutoff_seconds
    )
    @feeds_by_id = FeedsStore.all.each_with_object({}) { |f, h| h[f['id']] = f }
    erb :bus
  end

  get '/podcasts' do
    @page_title       = 'Podcasts'
    @shows            = ArticlesStore.podcast_feeds
    @recent_episodes  = ArticlesStore.recent(limit: 25, kind: :podcast)
    @feeds_by_id      = FeedsStore.all.each_with_object({}) { |f, h| h[f['id']] = f }
    erb :podcasts
  end

  # Stored digests, newest first. `make digest` (cron) appends to this
  # list; the detail view renders the saved html_body inline.
  get '/digests' do
    @page_title = 'Digests'
    @digests    = DigestStore.recent(limit: 100)
    erb :digests
  end

  get '/digests/:id' do |id|
    @digest = DigestStore.find(id)
    halt 404, 'Digest not found' unless @digest
    @page_title = @digest['subject']
    erb :digest
  end

  # Manual digest trigger — same code path as `make digest` (the cron
  # script), but kicked off from the /digests page button. Composition
  # is fast (one SQL pull + render, ~50ms typical) so we run inline
  # rather than enqueueing to Sidekiq. ?window_hours and ?limit
  # override the defaults if the user wants a longer or wider digest.
  post '/digests' do
    window = (params['window_hours'].to_s.match?(/\A\d+\z/) ? params['window_hours'].to_i : Digests::DEFAULT_WINDOW_HOURS).clamp(1, 720)
    limit  = (params['limit'].to_s.match?(/\A\d+\z/)        ? params['limit'].to_i        : Digests::DEFAULT_LIMIT).clamp(1, 200)
    id, result = Digests.generate_and_store!(window_hours: window, limit: limit)
    AppLogger.info('digest_manual_trigger', id: id, count: result.count, window_hours: window)
    redirect to("/digests/#{id}?notice=generated&count=#{result.count}")
  end

  get '/article/:uid' do |uid|
    @article = ArticlesStore.find_by_uid(uid)
    halt 404, erb(:article_not_found) unless @article

    @feed            = FeedsStore.find(@article['feed_id'])
    @state           = ReadStateStore.opened!(@article['id'])
    @article_tags    = TagsStore.tags_for_article(@article['id'])
    @all_tags        = TagsStore.all
    @summary         = SummaryStore.find(@article['id'])
    @claude_available = Summarizer::Claude.available?
    @related         = Recommendation.for_article(@article, limit: 5)
    @feeds_by_id     = FeedsStore.all.each_with_object({}) { |f, h| h[f['id']] = f }
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

    result = Summarizer::Claude.summarize(
      title:        article['title'].to_s,
      content_text: article['content_text'].to_s
    )

    case result.status
    when :ok
      SummaryStore.upsert(article['id'], llm: result.text, llm_model: result.model)
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
    ReadStateStore.mark_read(article['id'], read: read)
    redirect to(params['return_to'] || "/article/#{uid}")
  end

  post '/article/:uid/bookmark' do |uid|
    article = ArticlesStore.find_by_uid(uid)
    halt 404 unless article
    value = params['value'] != '0'
    ReadStateStore.mark_bookmarked(article['id'], value: value)
    redirect to(params['return_to'] || "/article/#{uid}")
  end

  post '/article/:uid/archive' do |uid|
    article = ArticlesStore.find_by_uid(uid)
    halt 404 unless article
    value = params['value'] != '0'
    ReadStateStore.mark_archived(article['id'], value: value)
    redirect to(params['return_to'] || "/article/#{uid}")
  end

  # Apply one read-state action to many articles in a single request,
  # so the /articles bulk-toolbar can mark / archive / bookmark a
  # selection in one round-trip instead of N. JSON in, JSON out;
  # returns a per-uid result list so the UI can flag any uids that
  # didn't resolve. Cap is 500 uids per call to keep the SQL bounded.
  BULK_ACTIONS = {
    'read'       => ->(id) { ReadStateStore.mark_read(id,       read:  true)  },
    'unread'     => ->(id) { ReadStateStore.mark_read(id,       read:  false) },
    'bookmark'   => ->(id) { ReadStateStore.mark_bookmarked(id, value: true)  },
    'unbookmark' => ->(id) { ReadStateStore.mark_bookmarked(id, value: false) },
    'archive'    => ->(id) { ReadStateStore.mark_archived(id,   value: true)  },
    'unarchive'  => ->(id) { ReadStateStore.mark_archived(id,   value: false) }
  }.freeze
  BULK_UIDS_MAX = 500

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
        handler.call(article['id'])
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
    @articles    = ArticlesStore.for_topic(@term, limit: 30)
    @feeds_by_id = FeedsStore.all.each_with_object({}) { |f, h| h[f['id']] = f }
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
    @feeds       = FeedsStore.all
    @notice      = params['notice']
    @error       = params['error']
    @catalog     = FeedCatalog.by_category
    @subscribed  = @feeds.map { |f| f['url'] }.to_set
    @categories  = FeedCatalog::CATEGORIES
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

    if FeedsStore.find_by_url(url)
      redirect to("/feeds?notice=already-subscribed&title=#{CGI.escape(entry[:title])}")
    else
      FeedsStore.add(url: entry[:url], title: entry[:title], fetch_interval_seconds: entry[:interval])
      redirect to("/feeds?notice=catalog-added&title=#{CGI.escape(entry[:title])}")
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

    begin
      FeedsStore.add(url: url, title: title, fetch_interval_seconds: interval)
      redirect to('/feeds?notice=added')
    rescue SQLite3::ConstraintException
      redirect to('/feeds?error=duplicate-url')
    end
  end

  # POST-for-delete because plain HTML forms only support GET / POST.
  # Cascades through articles → read_state / summaries / article_tags
  # via the FK chain in 001_init.sql.
  post '/feeds/:id/delete' do |id|
    if FeedsStore.remove(id.to_i)
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

    begin
      feed = FeedsStore.add(url: url, title: title, fetch_interval_seconds: interval)
      status 201
      { ok: true, feed: feed, row_html: render_feed_row(feed) }.to_json
    rescue SQLite3::ConstraintException
      status 422
      { ok: false, error: 'duplicate-url', message: 'That feed is already subscribed.' }.to_json
    end
  end

  delete '/api/feeds/:id' do |id|
    content_type :json
    if FeedsStore.remove(id.to_i)
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

    if (existing = FeedsStore.find_by_url(url))
      { ok: true, status: 'already-subscribed', feed: existing, row_html: render_feed_row(existing) }.to_json
    else
      feed = FeedsStore.add(url: entry[:url], title: entry[:title], fetch_interval_seconds: entry[:interval])
      status 201
      { ok: true, status: 'added', feed: feed, row_html: render_feed_row(feed) }.to_json
    end
  end

  post '/api/admin/refresh/all' do
    content_type :json
    feeds = FeedsStore.all
    feeds.each { |f| FeedRefreshWorker.perform_async(f['id']) }
    AppLogger.info('refresh_all_enqueued', count: feeds.length, source: 'api')
    { ok: true, queued: feeds.length }.to_json
  end

  post '/api/admin/refresh/:feed_id' do |feed_id|
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
        if FeedsStore.find_by_url(entry[:url])
          skipped += 1
        else
          FeedsStore.add(url: entry[:url], title: entry[:title])
          added += 1
        end
      end
      redirect to("/feeds?notice=imported&added=#{added}&skipped=#{skipped}&total=#{entries.length}")
    rescue StandardError => e
      redirect to("/feeds?error=import-failed&msg=#{CGI.escape(e.message)}")
    end
  end

  # Export every subscribed feed as OPML 2.0 — moves the feed list to
  # any other reader (or back into a fresh tech-feed-reader install).
  get '/feeds/export.opml' do
    content_type 'text/x-opml'
    attachment "tech-feed-reader-feeds-#{Date.today}.opml"
    OPML.build(FeedsStore.all)
  end

  get '/tags' do
    @page_title     = 'Tags'
    @tags           = TagsStore.all
    @article_counts = TagsStore.article_counts
    @feeds_by_id    = FeedsStore.all.each_with_object({}) { |f, h| h[f['id']] = f }
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
      tag    = TagsStore.add(name: name, match_kind: kind, match_value: val)
      tagged = TagsApplier.apply_to_existing(tag['id'])
      redirect to("/tags?notice=added&tagged=#{tagged}")
    rescue SQLite3::ConstraintException
      redirect to('/tags?error=duplicate-name')
    end
  end

  post '/tags/:id/delete' do |id|
    if TagsStore.remove(id.to_i)
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
    halt 404 unless TagsStore.find(tag_id.to_i)

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
        @results = ArticlesStore.search(@query, limit: @per_page, offset: offset)
        @error   = nil
      rescue SQLite3::SQLException => e
        @results = []
        @error   = e.message
      end
    end

    @feeds_by_id     = FeedsStore.all.each_with_object({}) { |f, h| h[f['id']] = f }
    @tags_by_article = TagsStore.tags_for_articles(@results.map { |a| a['id'] })
    @page_title      = @query.empty? ? 'Search' : "Search: #{@query}"
    erb :search
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
      unread:        ReadStateStore.unread_count,
      bookmarked:    ReadStateStore.bookmarked_count,
      tags:          TagsStore.count,
      article_tags:  db.execute('SELECT COUNT(*) AS c FROM article_tags').first['c'],
      summaries:     db.execute('SELECT COUNT(*) AS c FROM summaries').first['c'],
      summaries_llm: db.execute("SELECT COUNT(*) AS c FROM summaries WHERE llm IS NOT NULL AND llm != ''").first['c']
    }

    @db_path  = Database.path
    @db_bytes =
      if @db_path == ':memory:'
        0
      else
        # Main file + WAL + shared-memory file. Each absent in fresh /
        # newly-checkpointed databases — guard with File.exist?.
        %W[#{@db_path} #{@db_path}-wal #{@db_path}-shm]
          .sum { |f| File.exist?(f) ? File.size(f) : 0 }
      end

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

  get '/admin/cache' do
    @page_title  = 'Cache admin'
    @feeds       = FeedsStore.all
    @article_counts = Database.connection
      .execute('SELECT feed_id, COUNT(*) AS c FROM articles GROUP BY feed_id')
      .each_with_object({}) { |row, h| h[row['feed_id']] = row['c'] }
    erb :admin_cache
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

  # Refresh every feed in FeedsStore. Iterates synchronously; for the
  # default starter set (5 feeds) this is fine. The scheduler script
  # (TODO-009) is the right tool once polling cadence matters.
  #
  # NOTE: /all must be declared before the :feed_id variant so Sinatra
  # matches the static path first. Otherwise the URL string "all" gets
  # parsed as a feed_id (= 0) and the request 404s.
  post '/admin/refresh/all' do
    feeds = FeedsStore.all
    feeds.each { |f| FeedRefreshWorker.perform_async(f['id']) }
    AppLogger.info('refresh_all_enqueued', count: feeds.length)
    redirect to("/feeds?notice=queued-all&count=#{feeds.length}")
  end

  # Refresh a single feed: enqueue a FeedRefreshWorker job. Returns
  # immediately; the worker process picks the job off the queue and
  # does the fetch + sanitize + import.
  post '/admin/refresh/:feed_id' do |feed_id|
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
# In test env we never start the server (rspec uses Rack::Test against
# TechFeedReader directly), so this whole block is gated on direct
# script invocation.
if __FILE__ == $PROGRAM_NAME
  require 'sidekiq/web'
  require 'rack/session/cookie'
  require 'securerandom'
  require 'rackup/handler'

  Sidekiq::Web.use Rack::Session::Cookie,
                   secret:    ENV['SIDEKIQ_WEB_SECRET'] || SecureRandom.hex(32),
                   same_site: :lax

  combined = Rack::Builder.app do
    map '/admin/sidekiq' do
      run Sidekiq::Web
    end
    map '/' do
      use MetricsMiddleware
      run TechFeedReader.new
    end
  end

  host = ENV['RACK_ENV'] == 'production' ? '0.0.0.0' : 'localhost'
  Rackup::Handler.get('puma').run(combined, Port: 4567, Host: host)
end
