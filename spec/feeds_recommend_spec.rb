require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/feed_catalog'

# Phase 4 (2026-05-12) — "Recommended for you" callout on /feeds.
# Scores unsubscribed catalog entries against the user's current
# subscriptions (category × 2 + topic × 1). Cold-start = empty.

RSpec.describe FeedCatalog, '.recommend_for' do
  it 'returns [] cold-start (no subscriptions overlap with the catalog)' do
    recs = FeedCatalog.recommend_for(subscribed_urls: [])
    expect(recs).to eq([])
  end

  it 'returns [] when subscriptions are all outside the catalog' do
    recs = FeedCatalog.recommend_for(subscribed_urls: ['https://example.com/random.rss'])
    expect(recs).to eq([])
  end

  it 'recommends entries in the same category as a single subscription' do
    # Subscribe to one tennis feed → recommend other tennis entries.
    tennis = FeedCatalog.all.find { |e| e[:category] == :tennis }
    recs = FeedCatalog.recommend_for(subscribed_urls: [tennis[:url]])
    expect(recs).not_to be_empty
    expect(recs.first[:category]).to eq(:tennis)
  end

  it 'does NOT recommend an already-subscribed entry' do
    tennis_entries = FeedCatalog.all.select { |e| e[:category] == :tennis }
    subscribed_urls = tennis_entries.map { |e| e[:url] }
    recs = FeedCatalog.recommend_for(subscribed_urls: subscribed_urls)
    recs.each do |entry|
      expect(subscribed_urls).not_to include(entry[:url])
    end
  end

  it 'category match scores 2× heavier than topic match' do
    # Subscribe to one :tennis (sports topic). Then a same-:tennis
    # unsubscribed entry should rank above e.g. an :nfl entry
    # (different category, same sports topic).
    tennis = FeedCatalog.all.find { |e| e[:category] == :tennis }
    recs = FeedCatalog.recommend_for(subscribed_urls: [tennis[:url]], limit: 30)
    tennis_idx = recs.index { |e| e[:category] == :tennis }
    nfl_idx    = recs.index { |e| e[:category] == :nfl }
    next unless tennis_idx && nfl_idx
    expect(tennis_idx).to be < nfl_idx
  end

  it 'caps the result to :limit' do
    # Subscribe to a couple of broad-category entries; ask for 3.
    tech = FeedCatalog.all.find { |e| e[:category] == :publisher }
    recs = FeedCatalog.recommend_for(subscribed_urls: [tech[:url]], limit: 3)
    expect(recs.length).to be <= 3
  end
end

RSpec.describe 'GET /feeds — Recommended-for-you section' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'omits the recommended section when the user has no catalog subscriptions' do
    get '/feeds'
    expect(last_response.body).not_to include('Recommended for you')
  end

  it 'renders the recommended section once any catalog feed is subscribed' do
    tennis = FeedCatalog.all.find { |e| e[:category] == :tennis }
    FeedsStore.add(url: tennis[:url], title: tennis[:title])
    get '/feeds'
    expect(last_response.body).to include('Recommended for you')
    expect(last_response.body).to match(%r{feeds-recommended})
  end

  it 'recommended entries each have an inline + Add form' do
    tennis = FeedCatalog.all.find { |e| e[:category] == :tennis }
    FeedsStore.add(url: tennis[:url], title: tennis[:title])
    get '/feeds'
    rec_section = last_response.body[/<section class="benchmark-section feeds-recommended"[\s\S]*?<\/section>/]
    expect(rec_section).not_to be_nil
    expect(rec_section).to match(%r{<form[^>]*action="/feeds/catalog/add"})
  end
end
