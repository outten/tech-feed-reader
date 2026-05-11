require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/providers/itunes_lookup'

# STUFF.md follow-up — Apple Podcasts URL auto-resolution.
# Pasting `https://podcasts.apple.com/.../id<digits>` into POST /feeds
# used to silently fail (HTML page, parser imports 0 entries). Now the
# route detects the pattern, calls Providers::ITunesLookup.lookup_by_id,
# and rewrites to the resolved feedUrl before insert.

RSpec.describe Providers::ITunesLookup, '.apple_podcast_id_from_url' do
  it 'extracts the numeric ID from a canonical Apple Podcasts URL' do
    expect(Providers::ITunesLookup.apple_podcast_id_from_url(
      'https://podcasts.apple.com/us/podcast/thoughts-on-the-market/id1466686717'
    )).to eq('1466686717')
  end

  it 'handles a URL with trailing query string' do
    expect(Providers::ITunesLookup.apple_podcast_id_from_url(
      'https://podcasts.apple.com/us/podcast/show/id12345?i=1000'
    )).to eq('12345')
  end

  it 'returns nil for non-Apple URLs' do
    expect(Providers::ITunesLookup.apple_podcast_id_from_url('https://example.com/feed.rss')).to be_nil
  end

  it 'returns nil for an Apple URL without an id segment' do
    expect(Providers::ITunesLookup.apple_podcast_id_from_url('https://podcasts.apple.com/us/genre/podcasts')).to be_nil
  end
end

RSpec.describe Providers::ITunesLookup, '.lookup_by_id' do
  def http_response(code: '200', body:)
    instance_double(Net::HTTPResponse, code: code, body: body)
  end

  it 'returns :ok with feedUrl + collectionName + artwork when iTunes finds the show' do
    body = JSON.generate(resultCount: 1, results: [{
      collectionName: 'Thoughts on the Market',
      feedUrl: 'https://rss.art19.com/thoughts-on-the-market',
      artworkUrl600: 'https://example.com/art600.jpg',
      artworkUrl100: 'https://example.com/art100.jpg'
    }])
    result = Providers::ITunesLookup.lookup_by_id('1466686717',
                                                   http_get: ->(_) { http_response(body: body) })
    expect(result.status).to eq(:ok)
    expect(result.feed_url).to eq('https://rss.art19.com/thoughts-on-the-market')
    expect(result.collection_name).to eq('Thoughts on the Market')
    expect(result.artwork_url).to eq('https://example.com/art600.jpg')
  end

  it 'falls back to artworkUrl100 when 600 is missing' do
    body = JSON.generate(resultCount: 1, results: [{
      collectionName: 'X', feedUrl: 'https://example.com/x.rss',
      artworkUrl100: 'https://example.com/art100.jpg'
    }])
    result = Providers::ITunesLookup.lookup_by_id('42',
                                                   http_get: ->(_) { http_response(body: body) })
    expect(result.artwork_url).to eq('https://example.com/art100.jpg')
  end

  it 'returns :not_found when iTunes returns no results' do
    body = JSON.generate(resultCount: 0, results: [])
    result = Providers::ITunesLookup.lookup_by_id('999999',
                                                   http_get: ->(_) { http_response(body: body) })
    expect(result.status).to eq(:not_found)
  end

  it 'returns :not_found when the match has no feedUrl' do
    body = JSON.generate(resultCount: 1, results: [{ collectionName: 'No RSS show' }])
    result = Providers::ITunesLookup.lookup_by_id('1',
                                                   http_get: ->(_) { http_response(body: body) })
    expect(result.status).to eq(:not_found)
    expect(result.error).to include('no feedUrl')
  end

  it 'returns :error on non-2xx HTTP' do
    result = Providers::ITunesLookup.lookup_by_id('1',
                                                   http_get: ->(_) { http_response(code: '503', body: '') })
    expect(result.status).to eq(:error)
    expect(result.error).to include('503')
  end

  it 'returns :error on malformed JSON' do
    result = Providers::ITunesLookup.lookup_by_id('1',
                                                   http_get: ->(_) { http_response(body: 'not json') })
    expect(result.status).to eq(:error)
  end

  it 'returns :not_found on empty id' do
    expect(Providers::ITunesLookup.lookup_by_id('').status).to eq(:not_found)
  end
end

RSpec.describe 'POST /feeds with an Apple Podcasts URL' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  def stub_lookup_ok(feed_url:, collection:)
    result = Providers::ITunesLookup::LookupByIdResult.new(
      status: :ok, feed_url: feed_url, collection_name: collection, artwork_url: nil
    )
    allow(Providers::ITunesLookup).to receive(:lookup_by_id).and_return(result)
  end

  it 'auto-resolves an Apple Podcasts URL to the underlying RSS feed and adds it' do
    stub_lookup_ok(feed_url: 'https://rss.art19.com/thoughts-on-the-market',
                   collection: 'Thoughts on the Market')
    expect {
      post '/feeds', { url: 'https://podcasts.apple.com/us/podcast/thoughts-on-the-market/id1466686717' }
    }.to change { FeedsStore.count }.by(1)
    follow_redirect!
    expect(last_response.body).to include('Resolved that Apple Podcasts URL')
    added = FeedsStore.all.last
    expect(added['url']).to eq('https://rss.art19.com/thoughts-on-the-market')
    expect(added['title']).to eq('Thoughts on the Market')
  end

  it 'redirects with an error when iTunes returns :not_found' do
    allow(Providers::ITunesLookup).to receive(:lookup_by_id)
      .and_return(Providers::ITunesLookup::LookupByIdResult.new(status: :not_found))
    expect {
      post '/feeds', { url: 'https://podcasts.apple.com/us/podcast/x/id99999' }
    }.not_to change { FeedsStore.count }
    expect(last_response.headers['Location']).to include('apple-not-found')
  end

  it 'redirects with an error when iTunes lookup HTTP fails' do
    allow(Providers::ITunesLookup).to receive(:lookup_by_id)
      .and_return(Providers::ITunesLookup::LookupByIdResult.new(status: :error, error: 'HTTP 503'))
    post '/feeds', { url: 'https://podcasts.apple.com/us/podcast/x/id12345' }
    expect(last_response.headers['Location']).to include('apple-lookup-failed')
  end

  it 'does NOT try to resolve a normal RSS URL' do
    expect(Providers::ITunesLookup).not_to receive(:lookup_by_id)
    post '/feeds', { url: 'https://example.com/feed.rss' }
    follow_redirect!
    expect(last_response.body).to include('Feed added.')
  end
end
