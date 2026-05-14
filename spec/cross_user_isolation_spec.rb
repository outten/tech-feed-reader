require_relative 'spec_helper'
require_relative '../app/users_store'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/read_state_store'
require_relative '../app/feed_feedback_store'
require_relative '../app/mute_rules_store'
require_relative '../app/tags_store'
require_relative '../app/sports_follows_store'
require_relative '../app/triage_store'
require_relative '../app/digest_store'
require_relative '../app/digests'

# Phase A2.2 — cross-user isolation specs. Every per-user store should
# scope reads + writes to the calling user_id. We seed two users (the
# default t-money at id=1 from spec_helper, plus a second user "kate"),
# write data under each, and assert each user only sees their own rows.
RSpec.describe 'Phase A2.2 — cross-user isolation' do
  let(:kate) { UsersStore.create(username: 'kate', display_name: 'Kate') }
  let(:kate_id) { kate['id'] }
  let(:tmoney_id) { 1 }

  describe 'ReadStateStore' do
    let(:feed) { FeedsStore.add(url: 'https://iso.example.com/feed.xml') }
    before do
      ArticlesStore.import(feed_id: feed['id'], entries: [{
        uid: 'a' * 12, title: 'Iso article',
        url: 'https://iso.example.com/a', author: nil,
        published_at: '2026-05-13T12:00:00Z',
        content_html: '<p>x</p>', content_text: 'x'
      }])
    end
    let(:article) { ArticlesStore.find_by_uid('a' * 12) }

    it "doesn't leak read state across users" do
      ReadStateStore.mark_read(tmoney_id, article['id'])
      expect(ReadStateStore.get(tmoney_id, article['id'])['read']).to eq(1)
      expect(ReadStateStore.get(kate_id,   article['id'])['read']).to eq(0)
    end

    it "doesn't leak bookmarks across users" do
      ReadStateStore.mark_bookmarked(tmoney_id, article['id'])
      expect(ReadStateStore.bookmarked_count(tmoney_id)).to eq(1)
      expect(ReadStateStore.bookmarked_count(kate_id)).to eq(0)
    end

    it 'unread_count is per-user' do
      ReadStateStore.mark_read(tmoney_id, article['id'])
      # kate has the same subscription via FeedsStore.add (defaults to user 1
      # only — kate has zero subs and thus zero unread).
      FeedsStore.subscribe(kate_id, feed['id'])
      expect(ReadStateStore.unread_count(tmoney_id)).to eq(0)
      expect(ReadStateStore.unread_count(kate_id)).to eq(1)
    end

    it 'any_activity? flips only for the user who acted' do
      expect(ReadStateStore.any_activity?(tmoney_id)).to be(false)
      expect(ReadStateStore.any_activity?(kate_id)).to be(false)
      ReadStateStore.mark_read(kate_id, article['id'])
      expect(ReadStateStore.any_activity?(tmoney_id)).to be(false)
      expect(ReadStateStore.any_activity?(kate_id)).to be(true)
    end
  end

  describe 'TagsStore' do
    it 'lets the same tag name exist for two users' do
      t = TagsStore.add(user_id: tmoney_id, name: 'shared-name', match_kind: 'keyword', match_value: 'x')
      k = TagsStore.add(user_id: kate_id,   name: 'shared-name', match_kind: 'keyword', match_value: 'y')
      expect(t['id']).not_to eq(k['id'])
      expect(TagsStore.all(tmoney_id).map { |r| r['id'] }).to eq([t['id']])
      expect(TagsStore.all(kate_id).map { |r| r['id'] }).to eq([k['id']])
    end

    it 'find returns nil for a different user' do
      tag = TagsStore.add(user_id: tmoney_id, name: 'private', match_kind: 'keyword', match_value: 'x')
      expect(TagsStore.find(tmoney_id, tag['id'])).not_to be_nil
      expect(TagsStore.find(kate_id,   tag['id'])).to be_nil
    end
  end

  describe 'MuteRulesStore' do
    it "doesn't leak rules across users" do
      MuteRulesStore.add(user_id: tmoney_id, kind: 'keyword', value: 'crypto')
      expect(MuteRulesStore.all(tmoney_id).length).to eq(1)
      expect(MuteRulesStore.all(kate_id)).to be_empty
    end

    it 'the same (kind, value) can exist for two users' do
      expect(MuteRulesStore.add(user_id: tmoney_id, kind: 'keyword', value: 'nft')).to be(true)
      expect(MuteRulesStore.add(user_id: kate_id,   kind: 'keyword', value: 'nft')).to be(true)
    end
  end

  describe 'SportsFollowsStore' do
    it "doesn't leak follows across users" do
      SportsFollowsStore.add(user_id: tmoney_id, kind: 'team', value: 'eagles')
      SportsFollowsStore.add(user_id: kate_id,   kind: 'team', value: 'all-blacks')
      expect(SportsFollowsStore.for_kind(tmoney_id, 'team').map { |r| r['value'] }).to eq(['eagles'])
      expect(SportsFollowsStore.for_kind(kate_id,   'team').map { |r| r['value'] }).to eq(['all-blacks'])
    end

    it 'follow? is per-user' do
      SportsFollowsStore.add(user_id: tmoney_id, kind: 'player', value: 'sinner')
      expect(SportsFollowsStore.follow?(tmoney_id, 'player', 'sinner')).to be(true)
      expect(SportsFollowsStore.follow?(kate_id,   'player', 'sinner')).to be(false)
    end

    it 'distinct_values still unions across users (used by the sync cron)' do
      SportsFollowsStore.add(user_id: tmoney_id, kind: 'team', value: 'eagles')
      SportsFollowsStore.add(user_id: kate_id,   kind: 'team', value: 'all-blacks')
      expect(SportsFollowsStore.distinct_values('team')).to contain_exactly('eagles', 'all-blacks')
    end
  end

  describe 'FeedFeedbackStore' do
    let(:feed) { FeedsStore.add(url: 'https://ff.example.com/feed.xml') }

    it 'weight_for is per-user' do
      FeedFeedbackStore.bump(tmoney_id, feed['id'], direction: :up)
      FeedFeedbackStore.bump(tmoney_id, feed['id'], direction: :up)
      expect(FeedFeedbackStore.weight_for(tmoney_id, feed['id'])).to be > FeedFeedbackStore::DEFAULT_WEIGHT
      expect(FeedFeedbackStore.weight_for(kate_id,   feed['id'])).to eq(FeedFeedbackStore::DEFAULT_WEIGHT)
    end
  end

  describe 'TriageStore + DigestStore' do
    let(:triage_result) do
      Struct.new(:unread_count, :model, :must_read, :optional, :skip,
                 :status, :error, :latency_ms, :input_tokens, :output_tokens, :topic, :raw,
                 keyword_init: true)
        .new(unread_count: 0, model: 'm', must_read: [], optional: [], skip: [],
             status: 'ok', error: nil, latency_ms: 1, input_tokens: 1,
             output_tokens: 1, topic: nil, raw: '{}')
    end

    it "triage rows don't leak across users" do
      TriageStore.create(tmoney_id, triage_result)
      expect(TriageStore.count(tmoney_id)).to eq(1)
      expect(TriageStore.count(kate_id)).to eq(0)
    end

    it "digest rows don't leak across users" do
      DigestStore.create(tmoney_id, Digests::Result.new(
        subject: 's', text: 't', html: 'h', count: 0, window_hours: 24, generated_at: Time.now.utc
      ))
      expect(DigestStore.count(tmoney_id)).to eq(1)
      expect(DigestStore.count(kate_id)).to eq(0)
    end
  end

  describe 'FeedsStore + ArticlesStore' do
    let(:feed_a) { FeedsStore.add_to_catalog(url: 'https://a.example.com/feed.xml') }
    let(:feed_b) { FeedsStore.add_to_catalog(url: 'https://b.example.com/feed.xml') }
    before do
      # Subscribe explicitly so the two users have disjoint catalogs:
      # t-money → feed_a only, kate → feed_b only.
      FeedsStore.subscribe(tmoney_id, feed_a['id'])
      FeedsStore.subscribe(kate_id,   feed_b['id'])
      ArticlesStore.import(feed_id: feed_a['id'], entries: [{
        uid: 'a' * 12, title: 'Only for t-money',
        url: 'https://a.example.com/a', author: nil,
        published_at: '2026-05-13T12:00:00Z',
        content_html: '<p>x</p>', content_text: 'shared word'
      }])
      ArticlesStore.import(feed_id: feed_b['id'], entries: [{
        uid: 'b' * 12, title: 'Only for kate',
        url: 'https://b.example.com/b', author: nil,
        published_at: '2026-05-13T12:00:00Z',
        content_html: '<p>x</p>', content_text: 'shared word'
      }])
    end

    it 'for_user returns only the calling user\'s subscriptions' do
      expect(FeedsStore.for_user(tmoney_id).map { |f| f['id'] }).to eq([feed_a['id']])
      expect(FeedsStore.for_user(kate_id).map { |f| f['id'] }).to eq([feed_b['id']])
    end

    it 'ArticlesStore.recent only returns articles from feeds the user is subscribed to' do
      tm_titles = ArticlesStore.recent(tmoney_id).map { |a| a['title'] }
      k_titles  = ArticlesStore.recent(kate_id).map  { |a| a['title'] }
      expect(tm_titles).to eq(['Only for t-money'])
      expect(k_titles).to eq(['Only for kate'])
    end

    it 'ArticlesStore.search is scoped to subscriptions (same FTS term, different results per user)' do
      tm_uids = ArticlesStore.search(tmoney_id, 'shared').map { |a| a['uid'] }
      k_uids  = ArticlesStore.search(kate_id,   'shared').map { |a| a['uid'] }
      expect(tm_uids).to eq(['a' * 12])
      expect(k_uids).to eq(['b' * 12])
    end

    it 'unsubscribing one user leaves the other user\'s subscription intact' do
      FeedsStore.subscribe(kate_id, feed_a['id'])
      FeedsStore.unsubscribe(tmoney_id, feed_a['id'])
      expect(FeedsStore.subscribed?(tmoney_id, feed_a['id'])).to be(false)
      expect(FeedsStore.subscribed?(kate_id,   feed_a['id'])).to be(true)
      # Catalog row survives.
      expect(FeedsStore.find(feed_a['id'])).not_to be_nil
    end
  end

  describe 'Auth wall (route-level isolation)' do
    include Rack::Test::Methods
    def app; TechFeedReader; end

    around(:each) do |ex|
      require_relative '../app/main'
      TechFeedReader.enforce_auth_wall = true
      ex.run
    ensure
      TechFeedReader.enforce_auth_wall = false
    end

    it 'a logged-in user only sees their own bookmarks on /articles?state=bookmarked' do
      feed = FeedsStore.add(url: 'https://wall.example.com/feed.xml')
      FeedsStore.subscribe(kate_id, feed['id'])
      ArticlesStore.import(feed_id: feed['id'], entries: [{
        uid: 'a' * 12, title: 'Bookmarked by t-money',
        url: 'https://wall.example.com/a', author: nil,
        published_at: '2026-05-13T12:00:00Z',
        content_html: '<p>x</p>', content_text: 'x'
      }, {
        uid: 'b' * 12, title: 'Bookmarked by kate',
        url: 'https://wall.example.com/b', author: nil,
        published_at: '2026-05-13T12:00:00Z',
        content_html: '<p>y</p>', content_text: 'y'
      }])
      a = ArticlesStore.find_by_uid('a' * 12)
      b = ArticlesStore.find_by_uid('b' * 12)
      ReadStateStore.mark_bookmarked(tmoney_id, a['id'])
      ReadStateStore.mark_bookmarked(kate_id,   b['id'])

      # Sign in as t-money.
      env_run('/articles?state=bookmarked', as: tmoney_id) do
        expect(last_response.body).to include('Bookmarked by t-money')
        expect(last_response.body).not_to include('Bookmarked by kate')
      end

      # Sign in as kate.
      env_run('/articles?state=bookmarked', as: kate_id) do
        expect(last_response.body).to include('Bookmarked by kate')
        expect(last_response.body).not_to include('Bookmarked by t-money')
      end
    end

    # Helper: drive a GET through Rack::Test with a forged session cookie
    # for the given user_id, then yield to assertions.
    def env_run(path, as:)
      clear_cookies
      # Sinatra's session cookie store signs sessions; rather than reverse
      # the cookie format, hit the canonical sign-up path (we trust A1
      # ceremony specs to exercise the real flow) by directly setting
      # session[:user_id] via the test session's rack env hook.
      env = { 'rack.session' => { user_id: as } }
      get path, {}, env
      yield
    end
  end
end
