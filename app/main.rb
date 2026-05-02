require 'sinatra'
require 'sinatra/base'
require 'json'
require 'time'
require 'dotenv'

# Load credentials (Anthropic API key for Tier 2 summarization, etc.).
# `.credentials` is canonical; `.env` is a Dotenv default that we honour
# but don't write to. Both are git-ignored.
Dotenv.load(File.expand_path('../../.credentials', __FILE__))
Dotenv.load(File.expand_path('../../.env', __FILE__))

require_relative 'database'
require_relative 'feeds_store'

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
  end

  # ---- Routes ---------------------------------------------------------

  get '/' do
    redirect '/dashboard'
  end

  get '/dashboard' do
    @page_title = 'Dashboard'
    erb :dashboard
  end

  get '/articles' do
    @page_title = 'Articles'
    erb :articles
  end

  get '/article/:id' do |id|
    @page_title = 'Article'
    @article_id = id
    erb :article
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
    @page_title = 'Tags'
    erb :tags
  end

  get '/search' do
    @page_title = 'Search'
    @query = params['q'].to_s
    erb :search
  end

  get '/admin/health' do
    @page_title = 'Provider health'
    erb :admin_health
  end

  get '/admin/cache' do
    @page_title = 'Cache admin'
    erb :admin_cache
  end

  # ---- Boot -----------------------------------------------------------

  run! if app_file == $PROGRAM_NAME
end
