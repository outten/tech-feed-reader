require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'

# STUFF.md #19 — convention: internal app links (/article/:uid,
# /articles?..., /sports/...) open in the same tab; external
# publisher URLs (the article['url'] / @espn_url / picsum etc.) keep
# target="_blank" + rel="noopener noreferrer". /articles used to be
# the lone outlier and opened the title in a new tab — this spec
# locks the new convention across the listing surfaces.
RSpec.describe 'internal /article/:uid links stay in the same tab' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  def make_one_article(uid: 'targetlock001', title: 'Internal link test')
    feed = FeedsStore.add(url: "https://example.com/#{uid}-feed", title: 'Target lock feed')
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: uid, title: title,
      url: "https://example.com/#{uid}", author: nil,
      published_at: '2026-05-10T12:00:00Z',
      content_html: '<p>x</p>', content_text: 'x',
      audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
    }])
    ArticlesStore.find_by_uid(uid)
  end

  it '/articles renders the article title without target="_blank"' do
    make_one_article(uid: 'targetlock_a1')
    get '/articles'
    row = last_response.body[%r{<a class="news-row-main" href="/article/targetlock_a1"[^>]*>}]
    expect(row).not_to be_nil
    expect(row).not_to include('target="_blank"')
  end

  it '/article/:uid Read-next renders the next-article link without target="_blank"' do
    a = make_one_article(uid: 'targetlock_a2', title: 'First')
    b = make_one_article(uid: 'targetlock_a3', title: 'Second')
    get "/article/#{a['uid']}"
    # @read_next may or may not pick the other article, but if a
    # read-next-headline anchor exists it must not be _blank.
    if (rn = last_response.body[%r{<a class="read-next-headline" href="/article/[^"]+"[^>]*>}])
      expect(rn).not_to include('target="_blank"')
    end
  end

  # External (publisher) links MUST keep target="_blank" — confirm
  # we didn't strip too aggressively.
  it 'article reading view still opens the publisher Source link in a new tab' do
    a = make_one_article(uid: 'targetlock_a4', title: 'External keeps blank')
    get "/article/#{a['uid']}"
    expect(last_response.body).to match(
      %r{<a href="https://example\.com/targetlock_a4"[^>]*target="_blank"}
    )
  end
end
