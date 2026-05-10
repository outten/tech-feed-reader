require_relative 'spec_helper'
require_relative '../app/main'

# STUFF.md #13 — public home + about pages. / always renders the
# marketing home (no cookie redirect — newbies always land on the
# vision page; existing users use the nav Dashboard link).
# STUFF.md #14 — for returning users (any read_state activity in the
# DB), the hero swaps from "Stop swivel-chairing" to "Welcome back"
# with stats + top picks; the feature cards stay visible below.
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/read_state_store'

RSpec.describe 'GET /' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'renders the marketing home + a CTA to /dashboard (anonymous)' do
    get '/'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Stop swivel-chairing')
    expect(last_response.body).to include('href="/dashboard"')
  end

  it 'does not set a tfr_seen cookie (cookie-redirect was removed)' do
    get '/'
    expect(last_response.headers['Set-Cookie'].to_s).not_to include('tfr_seen')
  end

  # STUFF.md #14 — personalized hero for returning users.
  it 'swaps the hero to "Welcome back" + stats once read_state has any activity' do
    feed = FeedsStore.add(url: 'https://example.com/home-feed.rss')
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: 'home0001returning', title: 'Activity sentinel',
      url: 'https://example.com/a', author: nil,
      published_at: '2026-05-09T12:00:00Z',
      content_html: '<p>x</p>', content_text: 'x',
      audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
    }])
    article = ArticlesStore.find_by_uid('home0001returning')
    ReadStateStore.mark_bookmarked(article['id'], value: true)

    get '/'
    expect(last_response.body).to include('Welcome back')
    expect(last_response.body).not_to include('Stop swivel-chairing')
    expect(last_response.body).to include('Read your top picks')
    # Feature cards stay visible below the personalized hero.
    expect(last_response.body).to include('Ranked for you')
  end

  it 'home renders all six feature sections + the screenshots' do
    get '/'
    %w[
      One\ inbox\ for\ everything
      Ranked\ for\ you
      AI-assisted\ triage
      Summaries\ you\ can\ skim
      Podcasts\ that\ follow\ you
      Sports
    ].each do |fragment|
      expect(last_response.body).to include(fragment)
    end
    %w[dashboard for-you triage digest podcasts sports].each do |slug|
      expect(last_response.body).to include("/img/home/#{slug}.png")
    end
  end
end

RSpec.describe 'GET /about' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'renders the about page with the philosophy + tech sections' do
    get '/about'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('About Tech Feed Reader')
    expect(last_response.body).to include('Why this exists')
    expect(last_response.body).to include('How it works')
    expect(last_response.body).to include('Tech stack')
  end

  it 'links from the global footer on every page' do
    get '/dashboard'
    expect(last_response.body).to match(%r{<a href="/about"})
  end
end

# STUFF.md #14 — the header title is a link to / with data-turbo="false"
# so a click does a full document refresh rather than a Turbo SPA swap.
RSpec.describe 'header title link (STUFF.md #14)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'renders the title as a link to / with data-turbo="false"' do
    get '/dashboard'
    expect(last_response.body).to match(
      %r{<a class="logo"[^>]*href="/"[^>]*data-turbo="false"[^>]*>Tech Feed Reader</a>}
    )
  end

  # The Dashboard nav link opts out of Turbo so Chart.js inits cleanly
  # on a full document load. Turbo SPA nav left the Activity chart blank
  # in some browser/state combos despite the turbo:load fallback in
  # views/dashboard.erb (PR #65).
  it 'opts the Dashboard nav link out of Turbo' do
    get '/'
    expect(last_response.body).to match(%r{<a href="/dashboard"[^>]*data-turbo="false"})
  end
end
