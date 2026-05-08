require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/read_state_store'
require_relative '../app/recommendation/for_you'

# Phase 7 — Read-next suggestion below the article body. Two layers:
#   1. Recommendation::ForYou.next_after  (module-level picker + fallback gate)
#   2. /article/:uid view-surface         (card present + correct fallback path)

def make_read_next_article(uid:, title:, content_text: 'placeholder body text', published_at: '2026-05-06T12:00:00Z',
                           feed_url: 'https://x.com/readnext-rss', feed_title: 'Read Next Feed')
  feed = FeedsStore.find_by_url(feed_url) || FeedsStore.add(url: feed_url, title: feed_title)
  ArticlesStore.import(feed_id: feed['id'], entries: [{
    uid: uid, title: title, url: "https://x.com/#{uid}",
    author: nil, published_at: published_at,
    content_html: "<p>#{content_text}</p>", content_text: content_text,
    audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
  }])
  [feed, ArticlesStore.find_by_uid(uid)]
end

RSpec.describe Recommendation::ForYou, '#next_after (Phase 7)' do
  it 'returns nil when the positive corpus is empty (caller falls back)' do
    _, art = make_read_next_article(uid: 'rn00000001', title: 'A')
    expect(Recommendation::ForYou.next_after(art)).to be_nil
  end

  it 'returns nil when given nil article' do
    expect(Recommendation::ForYou.next_after(nil)).to be_nil
  end

  it 'returns the top-scored unread when corpus has signal' do
    # Seed positive corpus with a Ruby/Rails bookmark.
    _, pos = make_read_next_article(uid: 'rnpositive01', title: 'Rails routing deep dive', content_text: 'rails ruby routing')
    ReadStateStore.mark_bookmarked(pos['id'], value: true)
    ReadStateStore.mark_read(pos['id'], read: true)

    # Two unread candidates — one matches the corpus, one doesn't.
    make_read_next_article(uid: 'rnmatch00001', title: 'Advanced Rails performance tuning')
    make_read_next_article(uid: 'rnnomatch0001', title: 'Coffee origin guide')

    # Caller article is yet a third unread piece (not in corpus, not the candidate).
    _, current = make_read_next_article(uid: 'rncurrent0001', title: 'Something unrelated')

    nxt = Recommendation::ForYou.next_after(current)
    expect(nxt).not_to be_nil
    expect(nxt['uid']).to eq('rnmatch00001')
  end

  it 'excludes the current article from the suggestion' do
    # Make the current article match the corpus terms — it would be the
    # top scorer if not for the explicit exclusion.
    _, pos = make_read_next_article(uid: 'rnposcurr001', title: 'Rails routing deep dive')
    ReadStateStore.mark_bookmarked(pos['id'], value: true)
    ReadStateStore.mark_read(pos['id'], read: true)

    _, current = make_read_next_article(uid: 'rncurrent0002', title: 'Rails routing companion')
    make_read_next_article(uid: 'rnother00001', title: 'Coffee origin guide')

    nxt = Recommendation::ForYou.next_after(current)
    # Either the other unread candidate, or nil — but never the current article.
    expect(nxt && nxt['uid']).not_to eq('rncurrent0002')
  end
end

RSpec.describe 'GET /article/:uid Read-next card (Phase 7)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'renders the Read-next card when there is a fallback FTS5 hit (cold start)' do
    # No corpus, but two articles with overlapping body text — the
    # FTS5 fallback should pick the second.
    _, _ = make_read_next_article(uid: 'rnview000001', title: 'Apples and oranges',
                                  content_text: 'apples oranges fruit comparison')
    _, _ = make_read_next_article(uid: 'rnview000002', title: 'More fruit thoughts',
                                  content_text: 'apples oranges fruit are great')

    get '/article/rnview000001'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to match(%r{<aside class="read-next-card"[^>]*>})
    expect(last_response.body).to include('related pick')
    expect(last_response.body).to include('More fruit thoughts')
  end

  it 'renders the relevance-pick label when the For You ranker provides the suggestion' do
    _, pos = make_read_next_article(uid: 'rnviewpos001', title: 'Rails routing deep dive', content_text: 'rails ruby routing')
    ReadStateStore.mark_bookmarked(pos['id'], value: true)
    ReadStateStore.mark_read(pos['id'], read: true)

    make_read_next_article(uid: 'rnviewmatch01', title: 'Advanced Rails performance tuning')
    _, current = make_read_next_article(uid: 'rnviewcurr01', title: 'Something unrelated')

    get '/article/rnviewcurr01'
    expect(last_response.body).to include('relevance pick')
    expect(last_response.body).to include('Advanced Rails performance tuning')
  end

  it 'omits the card when neither corpus nor FTS5 has anything to suggest' do
    # Single article in the DB — no related, no corpus.
    _, _ = make_read_next_article(uid: 'rnviewlone01', title: 'Lonely', content_text: 'unique content')
    get '/article/rnviewlone01'
    expect(last_response.body).not_to include('class="read-next-card"')
    expect(last_response.body).not_to include('class="read-next-sentinel"')
  end

  it 'never points the card back at the current article' do
    _, pos = make_read_next_article(uid: 'rnviewself01', title: 'Self pos', content_text: 'matching content')
    ReadStateStore.mark_bookmarked(pos['id'], value: true)
    ReadStateStore.mark_read(pos['id'], read: true)
    _, current = make_read_next_article(uid: 'rnviewself02', title: 'Self test', content_text: 'matching content')

    get '/article/rnviewself02'
    # No back-pointer to the current uid.
    expect(last_response.body).not_to include('href="/article/rnviewself02" target="_blank"')
  end

  it 'opens the suggested article in a new tab' do
    make_read_next_article(uid: 'rnviewtab01', title: 'A',  content_text: 'shared body terms here')
    make_read_next_article(uid: 'rnviewtab02', title: 'B',  content_text: 'shared body terms here')
    get '/article/rnviewtab01'
    expect(last_response.body).to match(%r{<a class="read-next-headline" href="/article/rnviewtab02"[^>]*target="_blank"})
  end
end
