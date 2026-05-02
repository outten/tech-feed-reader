require_relative 'spec_helper'
require_relative '../app/feed_fetcher'
require_relative '../app/feeds_store'

RSpec.describe FeedFetcher do
  let(:rss_body) { File.read(File.expand_path('fixtures/rss20.xml', __dir__)) }
  let(:feed)     { FeedsStore.add(url: 'https://example.com/feed.rss') }

  def stub_response(code:, body: '', headers: {})
    klass = case code
            when 200..299 then Net::HTTPSuccess
            when 304      then Net::HTTPNotModified
            when 400..499 then Net::HTTPClientError
            when 500..599 then Net::HTTPServerError
            else Net::HTTPResponse
            end
    response = instance_double(klass, code: code.to_s, body: body)
    allow(response).to receive(:[]) { |key| headers[key] }
    allow(Providers::HttpClient).to receive(:get).and_return(response)
    response
  end

  describe '200 response' do
    before do
      stub_response(
        code:    200,
        body:    rss_body,
        headers: {
          'ETag'          => 'W/"abc123"',
          'Last-Modified' => 'Fri, 02 May 2026 12:00:00 GMT'
        }
      )
    end

    it 'returns :ok with normalised entries' do
      result = FeedFetcher.fetch_feed(feed)
      expect(result.status).to eq(:ok)
      expect(result.entries.length).to eq(2)
      expect(result.entries.first[:title]).to eq('Hello, world')
      expect(result.entries.first[:content_html]).not_to include('<script>')
    end

    it 'records etag / last_modified / last_status / last_fetched_at on the feed' do
      result = FeedFetcher.fetch_feed(feed)
      expect(result.feed['last_etag']).to eq('W/"abc123"')
      expect(result.feed['last_modified']).to eq('Fri, 02 May 2026 12:00:00 GMT')
      expect(result.feed['last_status']).to eq('200')
      expect(result.feed['last_fetched_at']).not_to be_nil
    end

    it 'backfills the feed title when previously unset' do
      result = FeedFetcher.fetch_feed(feed)
      expect(result.feed['title']).to eq('Example Tech Blog')
    end

    it 'leaves a user-supplied title untouched' do
      titled = FeedsStore.add(url: 'https://other.example.com/rss', title: 'My Custom Name')
      stub_response(code: 200, body: rss_body, headers: {})
      result = FeedFetcher.fetch_feed(titled)
      expect(result.feed['title']).to eq('My Custom Name')
    end
  end

  describe '304 response' do
    before { stub_response(code: 304, body: '') }

    it 'returns :not_modified with no entries and updates last_status' do
      result = FeedFetcher.fetch_feed(feed)
      expect(result.status).to eq(:not_modified)
      expect(result.entries).to be_empty
      expect(result.feed['last_status']).to eq('304')
      expect(result.feed['last_fetched_at']).not_to be_nil
    end
  end

  describe '4xx response' do
    before { stub_response(code: 404, body: 'not found') }

    it 'returns :error and stamps last_status with the HTTP code' do
      result = FeedFetcher.fetch_feed(feed)
      expect(result.status).to eq(:error)
      expect(result.error).to include('HTTP 404')
      expect(result.feed['last_status']).to eq('404')
    end
  end

  describe 'transport errors' do
    before do
      allow(Providers::HttpClient).to receive(:get).and_raise(Net::ReadTimeout)
    end

    it 'returns :error with the exception captured and stamps last_status=error' do
      result = FeedFetcher.fetch_feed(feed)
      expect(result.status).to eq(:error)
      expect(result.error).to be_a(Net::ReadTimeout)
      expect(result.feed['last_status']).to eq('error')
    end
  end
end
