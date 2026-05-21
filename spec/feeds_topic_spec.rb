require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/feed_catalog'

# Sports Phase S1 + S2 — top-level topic (technology / sports / general)
# on every feed, plus the seed catalog gaining sports entries.

def make_topical_article(uid:, title:, feed_topic:, feed_url: 'https://x.com/topical-rss', feed_title: 'Topical Feed')
  feed = FeedsStore.find_by_url(feed_url) || FeedsStore.add(url: feed_url, title: feed_title, topic: feed_topic)
  ArticlesStore.import(feed_id: feed['id'], entries: [{
    uid: uid, title: title, url: "https://x.com/#{uid}",
    author: nil, published_at: '2026-05-08T12:00:00Z',
    content_html: '<p>x</p>', content_text: 'x',
    audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
  }])
  [feed, ArticlesStore.find_by_uid(uid)]
end

RSpec.describe FeedsStore, '.add (Phase S1)' do
  it "defaults topic to 'general' when not specified" do
    feed = FeedsStore.add(url: 'https://x.com/default-topic', title: 'Default')
    expect(feed['topic']).to eq('general')
  end

  it 'persists an explicit topic' do
    feed = FeedsStore.add(url: 'https://x.com/sports', title: 'Sports', topic: 'sports')
    expect(feed['topic']).to eq('sports')
  end

  it 'allows updating topic via .update' do
    feed = FeedsStore.add(url: 'https://x.com/upd', title: 'Upd')
    FeedsStore.update(feed['id'], topic: 'technology')
    expect(FeedsStore.find(feed['id'])['topic']).to eq('technology')
  end
end

RSpec.describe FeedCatalog, 'Phase S1 + S2' do
  it 'declares a TOPICS constant covering technology + sports + nature' do
    expect(FeedCatalog::TOPICS.keys).to contain_exactly(:technology, :sports, :nature)
  end

  it 'every category in CATEGORIES has a topic mapping' do
    extra = FeedCatalog::CATEGORIES.keys - FeedCatalog::CATEGORY_TO_TOPIC.keys
    expect(extra).to be_empty
  end

  it 'topic_for derives the topic from a sub-category' do
    expect(FeedCatalog.topic_for(:aggregator)).to eq(:technology)
    expect(FeedCatalog.topic_for(:rugby)).to eq(:sports)
    expect(FeedCatalog.topic_for(:does_not_exist)).to eq(:general)
  end

  it 'topic_for accepts an entry hash' do
    entry = FeedCatalog.find_by_url('https://www.bleedinggreennation.com/rss/index.xml')
    expect(FeedCatalog.topic_for(entry)).to eq(:sports)
  end

  it 'has 37 sports entries spanning the original Phase S2 set + #52 PR3 breadth' do
    # Phase 2 follow-up added :youtube_sports as a parallel sports
    # sub-category. STUFF #52 PR3 added cricket / baseball / golf /
    # motorsport / horse_racing categories and 16 new feed entries
    # for the leagues that didn't have curated RSS before.
    sports_entries = FeedCatalog.all.select { |e| FeedCatalog.topic_for(e) == :sports }
    expect(sports_entries.length).to eq(37)
    expect(sports_entries.map { |e| e[:category] }.uniq).to contain_exactly(
      :nfl, :nba, :soccer, :rugby, :tennis, :youtube_sports,
      :cricket, :baseball, :golf, :motorsport, :horse_racing
    )
  end

  describe '.by_topic' do
    it 'returns a two-level nest keyed by topic then category' do
      tree = FeedCatalog.by_topic
      expect(tree.keys).to eq(FeedCatalog::TOPICS.keys)
      expect(tree[:technology]).to have_key(:aggregator)
      expect(tree[:sports]).to     have_key(:rugby)
      expect(tree[:sports][:rugby].length).to eq(4) # 2 news (BBC + RNZ) + 2 podcasts (Aotearoa Rugby Pod, GBR Aus/NZ)
    end
  end
end

RSpec.describe ArticlesStore, '.recent topic filter (Phase S1)' do
  it 'restricts to articles whose feed.topic matches when topic: is set' do
    make_topical_article(uid: 'topicart01', title: 'tech',   feed_topic: 'technology',
                          feed_url: 'https://x.com/tech-rss', feed_title: 'Tech Feed')
    make_topical_article(uid: 'topicart02', title: 'sports', feed_topic: 'sports',
                          feed_url: 'https://x.com/sports-rss', feed_title: 'Sports Feed')

    tech_uids   = ArticlesStore.recent(1, topic: 'technology').map { |a| a['uid'] }
    sports_uids = ArticlesStore.recent(1, topic: 'sports').map { |a| a['uid'] }
    all_uids    = ArticlesStore.recent(1).map { |a| a['uid'] }

    expect(tech_uids).to   include('topicart01')
    expect(tech_uids).not_to include('topicart02')
    expect(sports_uids).to     include('topicart02')
    expect(sports_uids).not_to include('topicart01')
    expect(all_uids).to        include('topicart01', 'topicart02')
  end

  it 'returns an empty array when topic matches no feed' do
    make_topical_article(uid: 'topicart03', title: 'one', feed_topic: 'technology')
    expect(ArticlesStore.recent(1, topic: 'sports')).to eq([])
  end

  it 'composes with state filter' do
    _, art = make_topical_article(uid: 'topicart04', title: 'sports unread', feed_topic: 'sports')
    expect(ArticlesStore.recent(1, topic: 'sports', state: :unread).map { |a| a['uid'] }).to include('topicart04')
    ReadStateStore.mark_read(1, art['id'], read: true)
    expect(ArticlesStore.recent(1, topic: 'sports', state: :unread).map { |a| a['uid'] }).not_to include('topicart04')
  end
end

RSpec.describe '/articles?topic= route (Phase S1)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'filters the rendered list by topic' do
    make_topical_article(uid: 'topicroute01', title: 'TechRow',   feed_topic: 'technology',
                         feed_url: 'https://x.com/tech-rss',   feed_title: 'TechFeed')
    make_topical_article(uid: 'topicroute02', title: 'SportsRow', feed_topic: 'sports',
                         feed_url: 'https://x.com/sports-rss', feed_title: 'SportsFeed')

    get '/articles?topic=sports'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to     include('SportsRow')
    expect(last_response.body).not_to include('TechRow')

    get '/articles?topic=technology'
    expect(last_response.body).to     include('TechRow')
    expect(last_response.body).not_to include('SportsRow')
  end

  it 'ignores invalid topic values' do
    make_topical_article(uid: 'topicroute03', title: 'AnyRow', feed_topic: 'technology')
    get '/articles?topic=bogus'
    expect(last_response.body).to include('AnyRow')
  end

  it 'preserves topic across state-filter chip toggles via filter_url' do
    make_topical_article(uid: 'topicroute04', title: 'X', feed_topic: 'sports')
    get '/articles?topic=sports&state=unread'
    # The bookmarked chip is currently inactive — clicking it should
    # preserve topic + apply state=bookmarked.
    expect(last_response.body).to include('href="?state=bookmarked&amp;topic=sports"').or include('href="?state=bookmarked&topic=sports"')
    # STUFF #50 — the *active* state chip toggles off: clicking
    # "unread" while it's already on clears state but preserves topic.
    expect(last_response.body).to include('href="?topic=sports"')
  end
end

RSpec.describe 'POST /feeds/catalog/add (Phase S1)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'sets topic=sports when a sports catalog entry is added' do
    sports_url = 'https://www.bleedinggreennation.com/rss/index.xml'
    post '/feeds/catalog/add', { url: sports_url }
    expect(last_response.status).to eq(302)
    feed = FeedsStore.find_by_url(sports_url)
    expect(feed['topic']).to eq('sports')
  end

  it 'sets topic=technology when a tech catalog entry is added' do
    tech_url = 'https://news.ycombinator.com/rss'
    post '/feeds/catalog/add', { url: tech_url }
    feed = FeedsStore.find_by_url(tech_url)
    expect(feed['topic']).to eq('technology')
  end
end
