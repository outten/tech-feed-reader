require_relative 'spec_helper'
require_relative '../app/feed_parser'

RSpec.describe FeedParser do
  let(:rss_body)  { File.read(File.expand_path('fixtures/rss20.xml', __dir__)) }
  let(:atom_body) { File.read(File.expand_path('fixtures/atom.xml',  __dir__)) }

  describe '.parse (RSS 2.0)' do
    let(:result) { FeedParser.parse(rss_body, feed_url: 'https://example.com/feed.rss') }

    it 'extracts the channel title' do
      expect(result[:title]).to eq('Example Tech Blog')
    end

    it 'normalises every entry to the same shape' do
      e = result[:entries].first
      expect(e.keys).to contain_exactly(
        :uid, :title, :url, :author, :published_at, :content_html, :content_text,
        :image_url,
        :audio_url, :audio_mime_type, :audio_duration_seconds
      )
    end

    it 'stamps each entry with a stable SHA1[0,12] uid' do
      uid = result[:entries].first[:uid]
      expect(uid).to match(/\A[0-9a-f]{12}\z/)

      again = FeedParser.parse(rss_body, feed_url: 'https://example.com/feed.rss')
      expect(again[:entries].first[:uid]).to eq(uid)
    end

    it 'sanitizes script tags out of entry content_html' do
      e = result[:entries].first
      expect(e[:content_html]).not_to include('<script>')
      expect(e[:content_html]).to include('<em>emphasis</em>')
    end

    it 'sanitizes iframe out of content_html' do
      e = result[:entries][1]
      expect(e[:content_html]).not_to include('<iframe')
    end

    it 'derives content_text from the sanitized HTML (no tags)' do
      e = result[:entries].first
      expect(e[:content_text]).to include('First post body')
      expect(e[:content_text]).not_to include('<')
      expect(e[:content_text]).not_to include('script')
    end

    it 'sets published_at to ISO8601 UTC' do
      expect(result[:entries].first[:published_at]).to eq('2026-05-02T12:00:00Z')
    end
  end

  describe '.parse (Atom)' do
    let(:result) { FeedParser.parse(atom_body, feed_url: 'https://atom.example.com/feed.atom') }

    it 'extracts the feed title' do
      expect(result[:title]).to eq('Example Atom Feed')
    end

    it 'extracts both entries with sanitized content' do
      expect(result[:entries].length).to eq(2)
      first = result[:entries].first
      expect(first[:title]).to eq('Atom entry one')
      expect(first[:content_html]).to include('<strong>bold</strong>')
      expect(first[:content_html]).not_to include('<script>')
    end

    it 'falls back to summary when content is absent' do
      second = result[:entries][1]
      expect(second[:content_text]).to include('Plain summary')
    end
  end

  describe '.parse encoding handling' do
    it 'forces UTF-8 and scrubs invalid bytes without raising' do
      mojibake = (+rss_body).force_encoding(Encoding::ISO_8859_1)
      mojibake << "\xFF".b   # invalid UTF-8 byte
      expect {
        FeedParser.parse(mojibake, feed_url: 'https://example.com/feed.rss')
      }.not_to raise_error
    end
  end

  describe '.parse image extraction' do
    let(:podcast_body) { File.read(File.expand_path('fixtures/podcast_rss.xml', __dir__)) }
    let(:podcast)      { FeedParser.parse(podcast_body, feed_url: 'https://example.com/podcast/feed') }

    it 'extracts the channel-level cover art from <itunes:image>' do
      expect(podcast[:image_url]).to eq('https://cdn.example.com/show-cover.jpg')
    end

    it 'extracts per-entry image_url from <itunes:image> on the item' do
      ep12 = podcast[:entries].find { |e| e[:title].start_with?('Episode 12') }
      expect(ep12[:image_url]).to eq('https://cdn.example.com/ep-12-art.jpg')
    end

    it 'leaves image_url nil for entries without an image declaration' do
      ep11 = podcast[:entries].find { |e| e[:title].start_with?('Episode 11') }
      expect(ep11[:image_url]).to be_nil
    end

    it 'falls back to the first <img> in content_html when no feed-level image is declared' do
      body = <<~XML
        <?xml version="1.0"?>
        <rss version="2.0"><channel>
          <title>Inline Image Blog</title>
          <link>https://example.com/blog</link>
          <description>fixture</description>
          <item>
            <title>Hello</title>
            <link>https://example.com/blog/1</link>
            <guid>1</guid>
            <pubDate>Mon, 04 May 2026 12:00:00 +0000</pubDate>
            <description><![CDATA[Body. <img src="https://cdn.example.com/inline.jpg" alt="x"> more.]]></description>
          </item>
        </channel></rss>
      XML
      result = FeedParser.parse(body, feed_url: 'https://example.com/blog/feed')
      expect(result[:entries].first[:image_url]).to eq('https://cdn.example.com/inline.jpg')
    end

    it 'rejects relative <img> URLs (they would 404 outside the publisher origin)' do
      body = <<~XML
        <?xml version="1.0"?>
        <rss version="2.0"><channel>
          <title>Relative</title>
          <link>https://example.com/blog</link>
          <description>fixture</description>
          <item>
            <title>Hello</title>
            <link>https://example.com/blog/1</link>
            <guid>1</guid>
            <pubDate>Mon, 04 May 2026 12:00:00 +0000</pubDate>
            <description><![CDATA[Body. <img src="/relative/path.jpg"> more.]]></description>
          </item>
        </channel></rss>
      XML
      result = FeedParser.parse(body, feed_url: 'https://example.com/blog/feed')
      expect(result[:entries].first[:image_url]).to be_nil
    end

    it 'returns nil channel image_url when neither <itunes:image> nor <image> is present' do
      result = FeedParser.parse(rss_body, feed_url: 'https://example.com/feed.rss')
      expect(result[:image_url]).to be_nil
    end
  end

  describe '.uid_for' do
    it 'is stable across calls and 12 hex chars wide' do
      a = FeedParser.uid_for('https://feed.example.com', 'https://post.example.com')
      b = FeedParser.uid_for('https://feed.example.com', 'https://post.example.com')
      expect(a).to eq(b)
      expect(a).to match(/\A[0-9a-f]{12}\z/)
    end

    it 'differs for distinct (feed, post) pairs' do
      a = FeedParser.uid_for('https://feed.a.example.com', 'https://post.example.com')
      b = FeedParser.uid_for('https://feed.b.example.com', 'https://post.example.com')
      expect(a).not_to eq(b)
    end
  end
end
