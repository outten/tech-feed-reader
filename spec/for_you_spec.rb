require_relative 'spec_helper'
require 'set'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/read_state_store'
require_relative '../app/feed_feedback_store'
require_relative '../app/recommendation/for_you'

# Phase 6 — For You ranker. Tests cover four layers:
#   1. score_article (pure compute)
#   2. corpus selection (positive / negative)
#   3. score_window (the orchestrator that wires it all together)
#   4. /articles?sort=relevance route + view-surface

def make_article_for_you(uid:, title:, content_text: 'body content', published_at: '2026-05-06T12:00:00Z',
                         feed_url: 'https://x.com/foryou-rss', feed_title: 'For You Feed')
  feed = FeedsStore.find_by_url(feed_url) || FeedsStore.add(url: feed_url, title: feed_title)
  ArticlesStore.import(feed_id: feed['id'], entries: [{
    uid: uid, title: title, url: "https://x.com/#{uid}",
    author: nil, published_at: published_at,
    content_html: "<p>#{content_text}</p>", content_text: content_text,
    audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
  }])
  [feed, ArticlesStore.find_by_uid(uid)]
end

RSpec.describe Recommendation::ForYou, '#score_article (pure compute)' do
  # Frozen 'now' so recency tests are deterministic.
  let(:now) { Time.parse('2026-05-06T12:00:00Z').utc }
  # An article published exactly 'now' so recency = 1.0 (eliminates that
  # variable for the overlap-focused tests).
  let(:fresh) {
    { 'title' => 'Ruby on Rails performance tips', 'published_at' => now.iso8601, 'feed_id' => 1 }
  }

  it 'collapses to recency * feed_weight when both corpora are empty' do
    score = described_class.score_article(fresh, pos_terms: Set.new, neg_terms: Set.new,
                                                  feed_weight: 1.0, now: now)
    expect(score).to be_within(0.01).of(1.0) # fresh + default weight + neutral
  end

  it 'boosts when title overlaps the positive corpus' do
    pos_terms = %w[ruby rails performance].to_set
    boosted = described_class.score_article(fresh, pos_terms: pos_terms, neg_terms: Set.new,
                                                    feed_weight: 1.0, now: now)
    neutral = described_class.score_article(fresh, pos_terms: Set.new, neg_terms: Set.new,
                                                    feed_weight: 1.0, now: now)
    expect(boosted).to be > neutral
  end

  it 'demotes when title overlaps the negative corpus, but never zeros out' do
    neg_terms = %w[ruby rails performance tips].to_set
    demoted = described_class.score_article(fresh, pos_terms: Set.new, neg_terms: neg_terms,
                                                    feed_weight: 1.0, now: now)
    expect(demoted).to be > 0.0
    # Hard floor: neg_factor never below NEGATIVE_FLOOR
    expect(demoted).to be >= described_class::NEGATIVE_FLOOR * 0.999
  end

  it 'multiplies by per-feed weight (Phase 3 input)' do
    boosted = described_class.score_article(fresh, pos_terms: Set.new, neg_terms: Set.new,
                                                    feed_weight: 2.0, now: now)
    neutral = described_class.score_article(fresh, pos_terms: Set.new, neg_terms: Set.new,
                                                    feed_weight: 1.0, now: now)
    expect(boosted).to be_within(0.01).of(2.0 * neutral)
  end

  it 'decays with age — 48h half-life means score halves every 48h' do
    older = fresh.merge('published_at' => (now - 48 * 3600).iso8601)
    fresh_score = described_class.score_article(fresh, pos_terms: Set.new, neg_terms: Set.new,
                                                       feed_weight: 1.0, now: now)
    older_score = described_class.score_article(older, pos_terms: Set.new, neg_terms: Set.new,
                                                       feed_weight: 1.0, now: now)
    expect(older_score).to be_within(0.01).of(fresh_score / 2.0)
  end

  it 'overlap saturates — 10 matches scores the same as 5 (cap at OVERLAP_SAT)' do
    title = 'one two three four five six seven eight nine ten ruby rails performance tips'
    art_5  = { 'title' => 'one two three four five', 'published_at' => now.iso8601, 'feed_id' => 1 }
    art_10 = { 'title' => title, 'published_at' => now.iso8601, 'feed_id' => 1 }
    pos_terms = %w[one two three four five six seven eight nine ten].to_set
    s5  = described_class.score_article(art_5,  pos_terms: pos_terms, neg_terms: Set.new, feed_weight: 1.0, now: now)
    s10 = described_class.score_article(art_10, pos_terms: pos_terms, neg_terms: Set.new, feed_weight: 1.0, now: now)
    expect(s10).to be_within(0.001).of(s5) # both saturated
  end

  it 'positive + negative blend correctly (positive over a negative is still demoted)' do
    pos_terms = %w[ruby].to_set
    neg_terms = %w[rails performance tips].to_set
    blended = described_class.score_article(fresh, pos_terms: pos_terms, neg_terms: neg_terms,
                                                    feed_weight: 1.0, now: now)
    only_pos = described_class.score_article(fresh, pos_terms: pos_terms, neg_terms: Set.new,
                                                     feed_weight: 1.0, now: now)
    expect(blended).to be < only_pos
  end
end

RSpec.describe Recommendation::ForYou, '#corpus_terms' do
  it 'returns an empty set when no positive corpus rows exist' do
    expect(described_class.corpus_terms(1, positive: true)).to eq(Set.new)
  end

  it 'extracts terms from bookmarked + 👍 + passive +1 articles (positive corpus)' do
    _, a = make_article_for_you(uid: 'foryou000001', title: 'Ruby on Rails performance tips')
    ReadStateStore.mark_bookmarked(1, a['id'], value: true)

    _, b = make_article_for_you(uid: 'foryou000002', title: 'Sinatra microservice patterns')
    ReadStateStore.mark_feedback(1, b['id'], value: 1)

    terms = described_class.corpus_terms(1, positive: true)
    %w[ruby rails sinatra performance microservice patterns].each do |t|
      expect(terms).to include(t)
    end
  end

  it 'extracts terms from 👎 + passive -1 + archived-without-reading (negative corpus)' do
    _, a = make_article_for_you(uid: 'foryou000003', title: 'Crypto market volatility')
    ReadStateStore.mark_feedback(1, a['id'], value: -1)

    _, b = make_article_for_you(uid: 'foryou000004', title: 'NFT speculation guide')
    # archived without reading
    ReadStateStore.mark_archived(1, b['id'], value: true)

    terms = described_class.corpus_terms(1, positive: false)
    %w[crypto market volatility nft speculation guide].each do |t|
      expect(terms).to include(t)
    end
  end

  it 'archive + read does NOT count as negative (read+archive is the user filing it away, not rejecting it)' do
    _, a = make_article_for_you(uid: 'foryou000005', title: 'Filed away properly')
    ReadStateStore.mark_read(1, a['id'], read: true)
    ReadStateStore.mark_archived(1, a['id'], value: true)

    expect(described_class.corpus_terms(1, positive: false)).to be_empty
  end
end

RSpec.describe Recommendation::ForYou, '#score_window' do
  let(:now) { Time.parse('2026-05-06T12:00:00Z').utc }

  it 'returns the same set of articles as ArticlesStore.recent(1) when corpus is empty + weights default' do
    # Three articles, each with default feed weight and no feedback.
    %w[a b c].each_with_index do |slug, i|
      make_article_for_you(uid: "fyempty#{slug}001", title: "Article #{slug}",
                           published_at: (now - i * 3600).iso8601)
    end

    chronological = ArticlesStore.recent(1, state: :unread).map { |a| a['uid'] }
    relevance     = described_class.score_window(1, state: :unread, limit: 50, offset: 0, now: now).map { |a| a['uid'] }
    expect(relevance).to eq(chronological)
  end

  it 'floats positive-overlap articles to the top of the unread list' do
    # Negative corpus seed: 👎 on a "crypto" article.
    _, neg = make_article_for_you(uid: 'fynegseed001', title: 'Crypto rant', published_at: (now - 24 * 3600).iso8601)
    ReadStateStore.mark_feedback(1, neg['id'], value: -1)
    ReadStateStore.mark_read(1, neg['id'], read: true)

    # Positive corpus seed: bookmarked Ruby/Rails article.
    _, pos = make_article_for_you(uid: 'fyposseed001', title: 'Rails routing deep dive', published_at: (now - 24 * 3600).iso8601)
    ReadStateStore.mark_bookmarked(1, pos['id'], value: true)
    ReadStateStore.mark_read(1, pos['id'], read: true)

    # Two unread candidates: one matches the positive corpus (rails),
    # one matches neither. Same publish time so recency is equal.
    make_article_for_you(uid: 'fycandrails01', title: 'Advanced Rails performance tuning',
                         published_at: (now - 1 * 3600).iso8601)
    make_article_for_you(uid: 'fycandnone001', title: 'Coffee origin guide',
                         published_at: (now - 1 * 3600).iso8601)

    ranked = described_class.score_window(1, state: :unread, limit: 50, offset: 0, now: now)
    uids   = ranked.map { |a| a['uid'] }
    rails_idx = uids.index('fycandrails01')
    none_idx  = uids.index('fycandnone001')
    expect(rails_idx).not_to be_nil
    expect(none_idx).not_to  be_nil
    expect(rails_idx).to be < none_idx
  end

  it 'stamps each row with a _score key for inspection' do
    make_article_for_you(uid: 'fyscore000001', title: 'Score me')
    ranked = described_class.score_window(1, state: :unread, limit: 50, offset: 0, now: now)
    expect(ranked.first['_score']).to be_a(Float)
  end
end

RSpec.describe 'GET /articles?sort=relevance' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'renders the For You chip in inactive state by default' do
    make_article_for_you(uid: 'fyroute0001', title: 'A')
    get '/articles'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('class="for-you"')
    expect(last_response.body).to include('?state=unread&sort=relevance')
  end

  it 'renders the For You chip active when ?sort=relevance is set' do
    make_article_for_you(uid: 'fyroute0002', title: 'A')
    get '/articles?sort=relevance'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('class="active for-you"')
  end

  it 'forces state=unread when sort=relevance is on (so already-read articles disappear)' do
    _, a = make_article_for_you(uid: 'fyroute0003', title: 'Already read')
    ReadStateStore.mark_read(1, a['id'], read: true)
    make_article_for_you(uid: 'fyroute0004', title: 'Still unread')

    get '/articles?sort=relevance&state=all'
    expect(last_response.body).to     include('Still unread')
    expect(last_response.body).not_to include('Already read')
  end

  it 'preserves kind + view filters in the chip href round-trip' do
    make_article_for_you(uid: 'fyroute0005', title: 'A')
    get '/articles?sort=relevance&kind=podcast&view=skim'
    # The off-state state-filter chips should carry kind+view but no sort=relevance.
    expect(last_response.body).to include('href="?state=unread&kind=podcast&view=skim"')
  end

  it 'falls back to chronological for any sort value other than `relevance`' do
    make_article_for_you(uid: 'fyroute0006', title: 'A')
    get '/articles?sort=spaceship'
    expect(last_response.body).not_to include('class="active for-you"')
  end
end
