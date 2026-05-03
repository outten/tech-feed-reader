require_relative 'spec_helper'
require_relative '../app/feed_parser'

RSpec.describe 'FeedParser podcast extraction' do
  let(:body) { File.read(File.expand_path('fixtures/podcast_rss.xml', __dir__)) }
  let(:result) { FeedParser.parse(body, feed_url: 'https://example.com/podcast/feed') }
  let(:entries) { result[:entries] }

  it 'extracts enclosure url and mime type for audio episodes' do
    ep12 = entries.find { |e| e[:title].start_with?('Episode 12') }
    expect(ep12[:audio_url]).to eq('https://cdn.example.com/audio/ep-12.mp3')
    expect(ep12[:audio_mime_type]).to eq('audio/mpeg')
  end

  it 'parses hh:mm:ss itunes duration to seconds' do
    ep12 = entries.find { |e| e[:title].start_with?('Episode 12') }
    expect(ep12[:audio_duration_seconds]).to eq(1 * 3600 + 23 * 60 + 45)
  end

  it 'parses mm:ss itunes duration to seconds' do
    ep11 = entries.find { |e| e[:title].start_with?('Episode 11') }
    expect(ep11[:audio_duration_seconds]).to eq(42 * 60 + 15)
  end

  it 'accepts bare-seconds itunes duration' do
    ep10 = entries.find { |e| e[:title].start_with?('Episode 10') }
    expect(ep10[:audio_duration_seconds]).to eq(3600)
  end

  it 'leaves audio fields nil for entries without an enclosure' do
    bonus = entries.find { |e| e[:title].start_with?('Bonus') }
    expect(bonus[:audio_url]).to be_nil
    expect(bonus[:audio_mime_type]).to be_nil
    expect(bonus[:audio_duration_seconds]).to be_nil
  end

  describe 'non-audio enclosures' do
    let(:body_with_image) do
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>Mixed feed</title>
            <item>
              <title>Has an image enclosure, not audio</title>
              <link>https://example.com/post/1</link>
              <guid isPermaLink="false">post-1</guid>
              <pubDate>Fri, 01 May 2026 09:00:00 +0000</pubDate>
              <description>Body</description>
              <enclosure url="https://example.com/cover.jpg" type="image/jpeg" length="234567"/>
            </item>
          </channel>
        </rss>
      XML
    end

    it 'ignores image / video enclosures so the row stays a regular article' do
      e = FeedParser.parse(body_with_image, feed_url: 'https://example.com/feed').dig(:entries, 0)
      expect(e[:audio_url]).to be_nil
      expect(e[:audio_mime_type]).to be_nil
    end
  end
end
