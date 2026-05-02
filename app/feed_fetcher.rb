require 'time'
require_relative 'providers/http_client'
require_relative 'feed_parser'
require_relative 'feeds_store'
require_relative 'health_registry'

# Orchestrator: takes a feed row, GETs the URL with conditional-GET
# headers, parses on 200, records status + ETag + Last-Modified +
# fetched-at on the FeedsStore row, returns a Result.
#
# This module does NOT persist articles — that wiring lands when
# ArticlesStore is built (TODO-005). For now, callers receive normalised
# entries and can do what they like with them.
module FeedFetcher
  Result = Struct.new(
    :status,    # :ok | :not_modified | :error
    :feed,      # latest FeedsStore row (after the update)
    :entries,   # [] for :not_modified / :error; normalised entries on :ok
    :title,     # parsed feed title (only on :ok)
    :error,     # exception or HTTP code (only on :error)
    keyword_init: true
  )

  module_function

  # `feed` is a hash row from FeedsStore. Returns a Result. The fetch is
  # wrapped in HealthRegistry.measure so /admin/health surfaces latency
  # + status + degraded? state. The wrap is a no-op in test env unless
  # ENV['HEALTH_REGISTRY']=1.
  def fetch_feed(feed)
    HealthRegistry.measure(feed['id']) { fetch_feed_impl(feed) }
  end

  def fetch_feed_impl(feed)
    response = Providers::HttpClient.get(
      feed['url'],
      headers: {
        'If-Modified-Since' => feed['last_modified'],
        'If-None-Match'     => feed['last_etag']
      }
    )

    code = response.code.to_i
    case code
    when 304
      record_status(feed, status: '304')
      Result.new(status: :not_modified, feed: FeedsStore.find(feed['id']), entries: [])
    when 200..299
      parsed = FeedParser.parse(response.body, feed_url: feed['url'])
      record_status(
        feed,
        status:        code.to_s,
        last_etag:     response['ETag'],
        last_modified: response['Last-Modified'],
        backfill_title: feed['title'].nil? || feed['title'].to_s.empty? ? parsed[:title] : nil
      )
      Result.new(
        status:  :ok,
        feed:    FeedsStore.find(feed['id']),
        entries: parsed[:entries],
        title:   parsed[:title]
      )
    else
      record_status(feed, status: code.to_s)
      Result.new(status: :error, feed: FeedsStore.find(feed['id']), entries: [], error: "HTTP #{code}")
    end
  rescue StandardError => e
    record_status(feed, status: 'error')
    Result.new(status: :error, feed: FeedsStore.find(feed['id']), entries: [], error: e)
  end

  class << self
    private

    def record_status(feed, status:, last_etag: nil, last_modified: nil, backfill_title: nil)
      fields = {
        last_fetched_at: Time.now.utc.iso8601,
        last_status:     status
      }
      fields[:last_etag]     = last_etag     if last_etag
      fields[:last_modified] = last_modified if last_modified
      fields[:title]         = backfill_title if backfill_title

      FeedsStore.update(feed['id'], **fields)
    end
  end
end
