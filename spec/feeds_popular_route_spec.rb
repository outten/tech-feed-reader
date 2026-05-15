require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/users_store'

# STUFF #24 — "Popular with other readers" section on /feeds.
# Verifies the route renders the section markup once there are
# multiple users subscribing to feeds, and omits the section entirely
# when no feeds exist.
RSpec.describe 'GET /feeds — Popular with other readers section' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'omits the section on a brand-new instance with no feeds' do
    get '/feeds'
    expect(last_response.body).not_to include('Popular with other readers')
  end

  it 'renders the section once at least one feed is subscribed' do
    FeedsStore.add(url: 'https://news-a.example/rss', title: 'News A', topic: 'technology')
    get '/feeds'
    expect(last_response.body).to include('Popular with other readers')
    expect(last_response.body).to include('feeds-popular')
  end

  it 'renders one heading per non-empty type bucket' do
    FeedsStore.add(url: 'https://news-a.example/rss', title: 'News A', topic: 'technology')
    FeedsStore.add(url: 'https://sport-a.example/rss', title: 'Sport A', topic: 'sports')
    FeedsStore.add(url: 'https://www.youtube.com/feeds/videos.xml?channel_id=UCAAA', title: 'YT A', topic: 'nature')
    get '/feeds'
    body = last_response.body
    expect(body).to include('📰 News')
    expect(body).to include('🏟 Sports')
    expect(body).to include('🎬 YouTube')
    # No nature-only or podcast feeds → those buckets are silent.
    expect(body).not_to include('📺 Nature')
    expect(body).not_to include('🎧 Podcasts')
  end

  it 'shows subscriber count and a "Subscribed" badge for the current user' do
    FeedsStore.add(url: 'https://news-a.example/rss', title: 'News A', topic: 'technology')
    get '/feeds'
    body = last_response.body
    # Slice the popular section out so the assertions don't accidentally
    # match the same feed's row in another section on the page.
    section = body[/<section class="benchmark-section feeds-popular[\s\S]*?<\/section>/]
    expect(section).not_to be_nil
    expect(section).to include('1 subscriber')
    expect(section).to match(/✓ Subscribed/)
  end

  it 'shows an "+ Add" form for feeds the current user does not subscribe to' do
    # Seed a second user and subscribe THEM (not the default user) to a
    # feed — the feed should appear in the popular list with an Add
    # button rather than a Subscribed badge.
    kate = UsersStore.create(username: 'kate')
    feed = FeedsStore.add_to_catalog(url: 'https://news-a.example/rss', title: 'News A', topic: 'technology')
    FeedsStore.subscribe(kate['id'], feed['id'])
    get '/feeds'
    section = last_response.body[/<section class="benchmark-section feeds-popular[\s\S]*?<\/section>/]
    expect(section).not_to be_nil
    expect(section).to match(/\+ Add/)
    expect(section).not_to match(/✓ Subscribed/)
  end
end
