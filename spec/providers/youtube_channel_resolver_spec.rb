require_relative '../spec_helper'
require_relative '../../app/providers/youtube_channel_resolver'

# STUFF #30 — resolve various user-pasted YouTube references to the
# canonical RSS feed URL. http_get is dependency-injected so the suite
# never touches the real network.
RSpec.describe Providers::YouTubeChannelResolver do
  # Minimal fake — only `.code` and `.body` are read by the resolver.
  FakeHttpResponse = Struct.new(:code, :body)

  def fake_http(code:, body: '')
    ->(_url) { FakeHttpResponse.new(code.to_s, body) }
  end

  CHANNEL_HTML_WITH_JSON = <<~HTML.freeze
    <!DOCTYPE html><html><head>
    <meta property="og:title" content="PBS NewsHour">
    <meta property="og:url" content="https://www.youtube.com/channel/UCnp2WgGyc4VyB9HZeUjjeUw">
    </head><body>
    <script>var ytInitialData = {"channelId":"UCnp2WgGyc4VyB9HZeUjjeUw","more":"stuff"};</script>
    </body></html>
  HTML

  CHANNEL_HTML_WITHOUT_CHANNELID = <<~HTML.freeze
    <!DOCTYPE html><html><head><title>YouTube</title></head>
    <body><p>nothing here</p></body></html>
  HTML

  FEED_XML = <<~XML.freeze
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>BBC News</title>
      <entry></entry>
    </feed>
  XML

  describe '.resolve — direct UC channel id paths (no scrape)' do
    it 'resolves an already-canonical feed URL by fetching the feed XML for title' do
      result = described_class.resolve(
        'https://www.youtube.com/feeds/videos.xml?channel_id=UCabcdefghijklmnopqrstuv',
        http_get: fake_http(code: 200, body: FEED_XML)
      )
      expect(result.status).to eq(:ok)
      expect(result.channel_id).to eq('UCabcdefghijklmnopqrstuv')
      expect(result.title).to eq('BBC News')
      expect(result.feed_url).to eq('https://www.youtube.com/feeds/videos.xml?channel_id=UCabcdefghijklmnopqrstuv')
    end

    it 'resolves a /channel/UC… URL the same way' do
      result = described_class.resolve(
        'https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv',
        http_get: fake_http(code: 200, body: FEED_XML)
      )
      expect(result.status).to eq(:ok)
      expect(result.channel_id).to eq('UCabcdefghijklmnopqrstuv')
    end

    it 'resolves a bare UC… id' do
      result = described_class.resolve(
        'UCabcdefghijklmnopqrstuv',
        http_get: fake_http(code: 200, body: FEED_XML)
      )
      expect(result.status).to eq(:ok)
      expect(result.channel_id).to eq('UCabcdefghijklmnopqrstuv')
    end

    it 'returns :not_found when the feed XML 404s (invalid UC id)' do
      result = described_class.resolve(
        'UCabcdefghijklmnopqrstuv',
        http_get: fake_http(code: 404)
      )
      expect(result.status).to eq(:not_found)
    end
  end

  describe '.resolve — handle / legacy URL paths (HTML scrape)' do
    it 'resolves @PBSNewsHour by scraping the channel page' do
      result = described_class.resolve(
        '@PBSNewsHour',
        http_get: fake_http(code: 200, body: CHANNEL_HTML_WITH_JSON)
      )
      expect(result.status).to eq(:ok)
      expect(result.channel_id).to eq('UCnp2WgGyc4VyB9HZeUjjeUw')
      expect(result.title).to eq('PBS NewsHour')
      expect(result.feed_url).to end_with('?channel_id=UCnp2WgGyc4VyB9HZeUjjeUw')
    end

    it 'resolves a bare handle (no leading @)' do
      result = described_class.resolve(
        'PBSNewsHour',
        http_get: fake_http(code: 200, body: CHANNEL_HTML_WITH_JSON)
      )
      expect(result.status).to eq(:ok)
      expect(result.channel_id).to eq('UCnp2WgGyc4VyB9HZeUjjeUw')
    end

    it 'resolves a full handle URL' do
      result = described_class.resolve(
        'https://www.youtube.com/@PBSNewsHour',
        http_get: fake_http(code: 200, body: CHANNEL_HTML_WITH_JSON)
      )
      expect(result.status).to eq(:ok)
      expect(result.channel_id).to eq('UCnp2WgGyc4VyB9HZeUjjeUw')
    end

    it 'resolves a legacy /c/ custom URL' do
      result = described_class.resolve(
        'https://www.youtube.com/c/PBSNewsHour',
        http_get: fake_http(code: 200, body: CHANNEL_HTML_WITH_JSON)
      )
      expect(result.status).to eq(:ok)
      expect(result.channel_id).to eq('UCnp2WgGyc4VyB9HZeUjjeUw')
    end

    it 'falls back to the <link rel="canonical"> when the JSON channelId is missing' do
      html = <<~HTML
        <head>
        <link rel="canonical" href="https://www.youtube.com/channel/UCxxxxxxxxxxxxxxxxxxxxxx">
        <meta property="og:title" content="Some Channel">
        </head>
      HTML
      result = described_class.resolve(
        '@whatever',
        http_get: fake_http(code: 200, body: html)
      )
      expect(result.status).to eq(:ok)
      expect(result.channel_id).to eq('UCxxxxxxxxxxxxxxxxxxxxxx')
      expect(result.title).to eq('Some Channel')
    end

    it 'returns :not_found when the channel page is 404' do
      result = described_class.resolve(
        '@nope_does_not_exist',
        http_get: fake_http(code: 404)
      )
      expect(result.status).to eq(:not_found)
    end

    it 'returns :not_found when the HTML has no channelId we recognize' do
      result = described_class.resolve(
        '@suspicious',
        http_get: fake_http(code: 200, body: CHANNEL_HTML_WITHOUT_CHANNELID)
      )
      expect(result.status).to eq(:not_found)
    end

    it 'decodes HTML entities in the channel title' do
      html = <<~HTML
        <meta property="og:title" content="Rock &amp; Roll Channel">
        <script>{"channelId":"UCabcdefghijklmnopqrstuv"}</script>
      HTML
      result = described_class.resolve(
        '@rock',
        http_get: fake_http(code: 200, body: html)
      )
      expect(result.title).to eq('Rock & Roll Channel')
    end
  end

  describe '.resolve — rejection paths' do
    it 'returns :error on blank input' do
      result = described_class.resolve('   ', http_get: fake_http(code: 500))
      expect(result.status).to eq(:error)
    end

    it 'returns :error when the input is a non-YouTube URL' do
      result = described_class.resolve(
        'https://example.com/whatever',
        http_get: fake_http(code: 500)
      )
      expect(result.status).to eq(:error)
      expect(result.error).to include('not a recognizable YouTube')
    end

    it 'returns :error when the HTTP client raises (network failure)' do
      raising_http = ->(_url) { raise SocketError, 'DNS failure' }
      result = described_class.resolve('@anything', http_get: raising_http)
      expect(result.status).to eq(:error)
      expect(result.error).to include('SocketError')
    end
  end
end
