require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/feed_catalog'
require_relative '../app/users_store'

# First-time-user onboarding (/welcome). Fires when a signed-in user
# has zero feed subscriptions; offers topic chips that one-click-
# subscribe to curated catalog feeds and then redirect to /articles.

RSpec.describe 'Welcome onboarding flow' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  describe 'GET / redirect for new signed-in users' do
    it 'redirects to /welcome when signed-in user has zero subscriptions' do
      get '/'
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to include('/welcome')
    end

    it 'does NOT redirect once the user has at least one subscription' do
      FeedsStore.add(url: 'https://example.com/rss', title: 'Example')
      get '/'
      expect(last_response.status).to eq(200)
      # Stayed on / — body has the home-page content.
      expect(last_response.headers['Location']).to be_nil
    end
  end

  describe 'GET /welcome' do
    it 'renders four topic chips with starter-feed counts' do
      get '/welcome'
      expect(last_response.status).to eq(200)
      body = last_response.body
      %w[Technology Sports Nature Podcasts].each do |label|
        expect(body).to include(label)
      end
      # Each chip mentions its starter-feed count.
      expect(body).to match(/\d+ starter feeds/)
      expect(body).to include('Welcome,')
      expect(body).to include('action="/welcome/subscribe"')
    end

    it 'redirects back to / once the user has subscriptions' do
      FeedsStore.add(url: 'https://example.com/rss', title: 'Example')
      get '/welcome'
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to end_with('/')
    end
  end

  describe 'POST /welcome/subscribe' do
    it 'subscribes the user to every starter feed in each selected topic' do
      expect(FeedsStore.count_for_user(1)).to eq(0)

      post '/welcome/subscribe', topics: %w[technology podcasts]
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to include('notice=onboarded')

      tech_count    = FeedCatalog.starters_for_topic(:technology).length
      podcast_count = FeedCatalog.starters_for_topic(:podcasts).length
      expect(FeedsStore.count_for_user(1)).to eq(tech_count + podcast_count)
    end

    it 'ignores topic names that are not in the chip set' do
      post '/welcome/subscribe', topics: %w[technology nonsense ../etc/passwd]
      expect(FeedsStore.count_for_user(1)).to eq(FeedCatalog.starters_for_topic(:technology).length)
    end

    it 'redirects back to /welcome with no subscription when no topics are sent' do
      post '/welcome/subscribe'
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to include('/welcome')
      expect(FeedsStore.count_for_user(1)).to eq(0)
    end

    it 'is idempotent on a re-submit (existing subscriptions are not duplicated)' do
      post '/welcome/subscribe', topics: %w[technology]
      n1 = FeedsStore.count_for_user(1)
      post '/welcome/subscribe', topics: %w[technology]
      expect(FeedsStore.count_for_user(1)).to eq(n1)
    end

    it 'surfaces the onboarded notice on /articles after redirect' do
      post '/welcome/subscribe', topics: %w[technology]
      follow_redirect!
      expect(last_response.body).to include("You're set up")
      expect(last_response.body).to match(/Subscribed to <strong>\d+/)
    end
  end

  describe 'cross-user isolation (Phase A2)' do
    let!(:kate) { UsersStore.create(username: 'kate') }

    it "does not count other users' subscriptions when deciding whether to onboard" do
      # Kate is subscribed to one feed; user 1 still has none.
      # add_to_catalog (vs .add) does NOT auto-subscribe user 1.
      feed = FeedsStore.add_to_catalog(url: 'https://shared.example/rss', title: 'Shared')
      FeedsStore.subscribe(kate['id'], feed['id'])

      # Sanity: shared catalog feed exists, kate has a subscription,
      # but FeedsStore.count_for_user(1) should still be 0 → onboarding fires for user 1.
      expect(FeedsStore.count_for_user(1)).to eq(0)
      expect(FeedsStore.count_for_user(kate['id'])).to eq(1)
      get '/'
      expect(last_response.headers['Location']).to include('/welcome')
    end
  end
end

RSpec.describe FeedCatalog, '.starters_for_topic' do
  it 'returns hand-picked catalog entries for technology' do
    starters = described_class.starters_for_topic(:technology)
    expect(starters).not_to be_empty
    starters.each do |entry|
      expect(described_class::CATEGORY_TO_TOPIC[entry[:category]]).to eq(:technology)
    end
  end

  it 'returns YouTube channels for nature' do
    starters = described_class.starters_for_topic(:nature)
    expect(starters).not_to be_empty
    starters.each do |entry|
      expect(entry[:url]).to include('youtube.com/feeds/videos.xml')
    end
  end

  it 'returns podcasts for the podcasts pseudo-topic' do
    starters = described_class.starters_for_topic(:podcasts)
    expect(starters).not_to be_empty
    starters.each do |entry|
      expect(entry[:category]).to eq(:podcast)
    end
  end

  it 'silently skips URLs that no longer resolve in CATALOG (drift safety)' do
    stub_const("#{described_class}::ONBOARDING_STARTERS",
               described_class::ONBOARDING_STARTERS.merge(technology: ['https://nope.example.test/feed']))
    expect(described_class.starters_for_topic(:technology)).to eq([])
  end

  it 'returns [] for an unknown topic' do
    expect(described_class.starters_for_topic(:bogus)).to eq([])
  end
end
