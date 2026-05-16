require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/read_state_store'

# STUFF.md #13 / #14 / #17 — / has two modes:
#   • Anonymous (no read_state rows) → marketing pitch + feature
#     cards (preserved so newbies see the vision).
#   • Returning user → What's On Today: sports / read / listen /
#     watch sections personalized by follows + For You ranker.
# The Dashboard moved to /admin/dashboard (operational, not a daily
# surface). /whats-on and /dashboard are 301 redirects.
RSpec.describe 'GET / — anonymous' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  # Seed one subscription so the new welcome-onboarding redirect
  # (signed-in + zero subscriptions → /welcome) doesn't fire and the
  # marketing-pitch branch can render. The marketing path runs when
  # signed_in? is true but any_activity? is false — having a feed
  # subscription with no read_state still hits the marketing branch.
  before { FeedsStore.add(url: 'https://example.com/feed.rss', title: 'Example') }

  it 'renders the marketing pitch when there is no read_state activity' do
    get '/'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Stop swivel-chairing')
    expect(last_response.body).to include('Ranked for you')
  end

  it "no longer points the anonymous CTA at /dashboard (it points at /articles)" do
    get '/'
    expect(last_response.body).to match(%r{<a class="btn-primary"[^>]*href="/articles\?sort=relevance})
    # And no stale "Open dashboard" CTA on the marketing hero.
    expect(last_response.body).not_to match(%r{href="/dashboard"})
  end

  it 'does not set a tfr_seen cookie (cookie-redirect was removed)' do
    get '/'
    expect(last_response.headers['Set-Cookie'].to_s).not_to include('tfr_seen')
  end
end

RSpec.describe 'GET / — returning user' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  def seed_activity!
    feed = FeedsStore.add(url: 'https://example.com/home-feed.rss')
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: 'home_returning01', title: 'Activity sentinel',
      url: 'https://example.com/a', author: nil,
      published_at: Time.now.utc.iso8601,
      content_html: '<p>x</p>', content_text: 'x',
      audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
    }])
    ReadStateStore.mark_bookmarked(1, ArticlesStore.find_by_uid('home_returning01')['id'], value: true)
  end

  it 'renders the What\'s On Today header when read_state has activity' do
    seed_activity!
    get '/'
    expect(last_response.body).to include("What's On Today")
    expect(last_response.body).not_to include('Stop swivel-chairing')
  end

  it 'shows the article in the "To read today" section (matched by For You ranker)' do
    seed_activity!
    get '/'
    expect(last_response.body).to include('To read today')
    expect(last_response.body).to include('Activity sentinel')
  end

  it 'includes the per-user stats line in the subtitle' do
    seed_activity!
    get '/'
    # 1 article, 1 bookmark, 0 unread (the one article is bookmarked,
    # not read). Loose match on the stats line.
    expect(last_response.body).to match(/bookmarked.*1.*articles/m).or match(/<strong>1<\/strong>.*bookmarked/m)
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
    get '/admin/dashboard'
    expect(last_response.body).to match(%r{<a href="/about"})
  end

  it 'CTAs point at the new homes: / for the queue, /admin/dashboard for ops' do
    get '/about'
    expect(last_response.body).to include('href="/admin/dashboard"')
    expect(last_response.body).to include('What\'s on today')
  end
end

# STUFF.md #14 — header title is a link to / with data-turbo="false".
RSpec.describe 'header title link' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'renders the title as a link to / with data-turbo="false"' do
    get '/admin/dashboard'
    expect(last_response.body).to match(
      %r{<a class="logo"[^>]*href="/"[^>]*data-turbo="false"[^>]*>Tech Feed Reader</a>}
    )
  end
end

# The nav no longer carries Dashboard / What's On links — Dashboard
# moved to /admin (linked from the admin index); What's On is just /.
RSpec.describe 'main nav after Dashboard + What\'s On move' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'does NOT render a top-level Dashboard nav link' do
    get '/about'
    nav = last_response.body[%r{<nav>.*?</nav>}m]
    expect(nav).not_to include('>Dashboard<')
  end

  it 'does NOT render a top-level What\'s On nav link' do
    get '/about'
    nav = last_response.body[%r{<nav>.*?</nav>}m]
    expect(nav).not_to include('>What')
  end

  it 'admin index links to /admin/dashboard' do
    get '/admin'
    expect(last_response.body).to include('/admin/dashboard')
  end
end
