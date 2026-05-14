require_relative 'spec_helper'
require_relative '../app/feed_fetcher'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'

# End-to-end: stub the HTTP layer with a fixture, drive FeedFetcher, hand
# the result.entries to ArticlesStore.import, and assert the DB lands in
# the expected shape. This is the wiring path that the scheduler + the
# admin "refresh" button (TODO-006 / TODO-009) will exercise too.
RSpec.describe 'fetch → parse → sanitize → import' do
  let(:rss_body) { File.read(File.expand_path('fixtures/rss20.xml', __dir__)) }
  let!(:feed)    { FeedsStore.add(url: 'https://example.com/feed.rss') }

  def stub_http(code:, body: '', headers: {})
    klass = case code
            when 200..299 then Net::HTTPSuccess
            when 304      then Net::HTTPNotModified
            else               Net::HTTPResponse
            end
    response = instance_double(klass, code: code.to_s, body: body)
    allow(response).to receive(:[]) { |k| headers[k] }
    allow(Providers::HttpClient).to receive(:get).and_return(response)
  end

  it 'fetches a feed and persists every entry to the articles table' do
    stub_http(
      code:    200,
      body:    rss_body,
      headers: { 'ETag' => 'W/"v1"', 'Last-Modified' => 'Fri, 02 May 2026 12:00:00 GMT' }
    )

    result = FeedFetcher.fetch_feed(feed)
    expect(result.status).to eq(:ok)

    inserted = ArticlesStore.import(feed_id: feed['id'], entries: result.entries)
    expect(inserted).to eq(2)
    expect(ArticlesStore.count).to eq(2)
    expect(ArticlesStore.for_feed(1, feed['id']).map { |a| a['title'] })
      .to contain_exactly('Hello, world', 'Second post')
  end

  it 'is idempotent — re-fetching the same feed adds zero new articles' do
    stub_http(code: 200, body: rss_body, headers: {})
    first  = FeedFetcher.fetch_feed(feed)
    ArticlesStore.import(feed_id: feed['id'], entries: first.entries)

    stub_http(code: 200, body: rss_body, headers: {})
    second   = FeedFetcher.fetch_feed(feed)
    inserted = ArticlesStore.import(feed_id: feed['id'], entries: second.entries)
    expect(inserted).to eq(0)
    expect(ArticlesStore.count).to eq(2)
  end

  it 'sanitizes article HTML before storing — script tags never reach the DB' do
    stub_http(code: 200, body: rss_body, headers: {})
    result = FeedFetcher.fetch_feed(feed)
    ArticlesStore.import(feed_id: feed['id'], entries: result.entries)

    rows = ArticlesStore.for_feed(1, feed['id'])
    rows.each do |row|
      expect(row['content_html']).not_to include('<script')
      expect(row['content_html']).not_to include('<iframe')
    end
  end

  it 'populates articles_fts via the trigger so search works post-import' do
    stub_http(code: 200, body: rss_body, headers: {})
    result = FeedFetcher.fetch_feed(feed)
    ArticlesStore.import(feed_id: feed['id'], entries: result.entries)

    titles = ArticlesStore.search(1, 'first').map { |a| a['title'] }
    expect(titles).to include('Hello, world')
  end

  it 'records a 304 cleanly without inserting anything' do
    stub_http(code: 304, body: '')
    result = FeedFetcher.fetch_feed(feed)
    expect(result.status).to eq(:not_modified)
    expect(ArticlesStore.import(feed_id: feed['id'], entries: result.entries)).to eq(0)
    expect(ArticlesStore.count).to eq(0)
    expect(FeedsStore.find(feed['id'])['last_status']).to eq('304')
  end
end
