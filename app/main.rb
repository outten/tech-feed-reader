require 'sinatra'
require 'sinatra/base'
require 'json'
require 'time'
require 'cgi'
require 'dotenv'

# Load credentials (Anthropic API key for Tier 2 summarization, etc.).
# `.credentials` is canonical; `.env` is a Dotenv default that we honour
# but don't write to. Both are git-ignored.
Dotenv.load(File.expand_path('../../.credentials', __FILE__))
Dotenv.load(File.expand_path('../../.env', __FILE__))

require_relative 'database'
require_relative 'feeds_store'
require_relative 'articles_store'
require_relative 'read_state_store'
require_relative 'tags_store'
require_relative 'tags_applier'
require_relative 'feed_fetcher'
require_relative 'health_registry'
require_relative 'scheduler'

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

  helpers do
    # Cache-bust query string for static assets — same pattern as t-money so
    # CSS/JS edits show up on next render without a hard reload.
    def asset_mtime(rel_path)
      full = File.join(settings.root, rel_path)
      File.exist?(full) ? File.mtime(full).to_i : Time.now.to_i
    end

    # Used in feed-fetch UI; ISO8601 timestamps become "2 minutes ago".
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
  end

  # ---- Routes ---------------------------------------------------------

  get '/' do
    redirect '/dashboard'
  end

  get '/dashboard' do
    @page_title     = 'Dashboard'
    @articles       = ArticlesStore.recent(limit: 20, state: :unread)
    @feeds_by_id    = FeedsStore.all.each_with_object({}) { |f, h| h[f['id']] = f }
    @article_count  = ArticlesStore.count
    @unread_count   = ReadStateStore.unread_count
    @bookmark_count = ReadStateStore.bookmarked_count
    @feed_count     = FeedsStore.count
    @degraded       = HealthRegistry.degraded?
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

    @articles = if @tag_filter
                  ArticlesStore.for_tag(tag_id, limit: @per_page, offset: offset, state: @state_filter)
                elsif @feed_filter
                  ArticlesStore.for_feed(feed_id, limit: @per_page, offset: offset, state: @state_filter)
                else
                  ArticlesStore.recent(limit: @per_page, offset: offset, state: @state_filter)
                end

    @feeds_by_id     = FeedsStore.all.each_with_object({}) { |f, h| h[f['id']] = f }
    @tags_by_article = TagsStore.tags_for_articles(@articles.map { |a| a['id'] })
    erb :articles
  end

  get '/article/:uid' do |uid|
    @article = ArticlesStore.find_by_uid(uid)
    halt 404, erb(:article_not_found) unless @article

    @feed         = FeedsStore.find(@article['feed_id'])
    @state        = ReadStateStore.opened!(@article['id'])
    @article_tags = TagsStore.tags_for_article(@article['id'])
    @all_tags     = TagsStore.all
    @page_title   = @article['title']
    erb :article
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

  get '/feeds' do
    @page_title = 'Feeds'
    @feeds      = FeedsStore.all
    @notice     = params['notice']
    @error      = params['error']
    erb :feeds
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

  get '/admin/health' do
    @page_title    = 'Provider health'
    @observations  = HealthRegistry.observations.last(50).reverse
    @summary       = HealthRegistry.per_feed_summary
    @degraded      = HealthRegistry.degraded?
    @feeds_by_id   = FeedsStore.all.each_with_object({}) { |f, h| h[f['id']] = f }
    @enabled       = HealthRegistry.enabled?
    erb :admin_health
  end

  get '/admin/cache' do
    @page_title  = 'Cache admin'
    @feeds       = FeedsStore.all
    @article_counts = Database.connection
      .execute('SELECT feed_id, COUNT(*) AS c FROM articles GROUP BY feed_id')
      .each_with_object({}) { |row, h| h[row['feed_id']] = row['c'] }
    erb :admin_cache
  end

  # Refresh every feed in FeedsStore. Iterates synchronously; for the
  # default starter set (5 feeds) this is fine. The scheduler script
  # (TODO-009) is the right tool once polling cadence matters.
  #
  # NOTE: /all must be declared before the :feed_id variant so Sinatra
  # matches the static path first. Otherwise the URL string "all" gets
  # parsed as a feed_id (= 0) and the request 404s.
  post '/admin/refresh/all' do
    summary = { ok: 0, not_modified: 0, error: 0, imported: 0 }
    FeedsStore.all.each do |feed|
      result, imported = Scheduler.refresh_one(feed)
      summary[result.status] = (summary[result.status] || 0) + 1
      summary[:imported]    += imported
    end
    qs = summary.map { |k, v| "#{k}=#{v}" }.join('&')
    redirect to("/feeds?notice=refreshed-all&#{qs}")
  end

  # Refresh a single feed: fetch + parse + sanitize + import. Synchronous
  # (single-user app, no queue needed at v1). Redirects to /feeds with a
  # status notice so the form-based UI stays simple.
  post '/admin/refresh/:feed_id' do |feed_id|
    feed = FeedsStore.find(feed_id.to_i)
    redirect to('/feeds?error=not-found') unless feed

    result, imported = Scheduler.refresh_one(feed)
    redirect to("/feeds?notice=refreshed&status=#{result.status}&imported=#{imported}")
  end

  # ---- Boot -----------------------------------------------------------

  run! if app_file == $PROGRAM_NAME
end
