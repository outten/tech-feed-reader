require_relative 'spec_helper'
require_relative '../app/main'

# STUFF — YouTube descriptions arrive as plain text via the Atom feed.
# format_youtube_description_html linkifies URLs, marks up timestamps
# (data-seconds for the IFrame-API seek), and links hashtags to
# YouTube's search-by-hashtag URL. Output is HTML-safe.
RSpec.describe 'format_youtube_description_html' do
  let(:instance) { TechFeedReader.new! }
  let(:fmt) { ->(text) { instance.send(:format_youtube_description_html, text) } }

  it 'returns an empty string for nil / blank input' do
    expect(fmt.call(nil)).to eq('')
    expect(fmt.call('   ')).to eq('')
  end

  it 'escapes HTML entities so the description cannot inject markup' do
    out = fmt.call('<script>alert(1)</script> & "quoted"')
    expect(out).to include('&lt;script&gt;')
    expect(out).not_to include('<script>')
    expect(out).to include('&quot;quoted&quot;').or include('&#34;quoted&#34;')
  end

  describe 'URL auto-linking' do
    it 'wraps http and https URLs in anchor tags with rel="noopener noreferrer" and target="_blank"' do
      out = fmt.call('Subscribe: http://bit.ly/BBCEarthSub and https://www.bbcearth.com/newsletter')
      expect(out).to include('<a href="http://bit.ly/BBCEarthSub"')
      expect(out).to include('<a href="https://www.bbcearth.com/newsletter"')
      expect(out).to include('rel="noopener noreferrer"')
      expect(out).to include('target="_blank"')
      expect(out).to include('class="yt-link"')
    end

    it 'does not include trailing punctuation in the href (period, comma)' do
      out = fmt.call('Visit https://example.com, then https://example.org.')
      expect(out).to include('<a href="https://example.com"')
      expect(out).to include('<a href="https://example.org"')
      # The trailing punctuation should still appear in the rendered text
      expect(out).to include(',')
      expect(out).to include('.')
    end
  end

  describe 'timestamp linkification' do
    it 'converts MM:SS to a button with data-seconds' do
      out = fmt.call("0:00 Intro\n1:23 First topic\n45:00 Outro")
      expect(out).to include('data-seconds="0"')
      expect(out).to include('data-seconds="83"')   # 1*60 + 23
      expect(out).to include('data-seconds="2700"') # 45*60
      expect(out).to include('class="yt-timestamp"')
    end

    it 'converts HH:MM:SS for long videos' do
      out = fmt.call('1:23:45 Long-format chapter')
      # 1*3600 + 23*60 + 45 = 5025
      expect(out).to include('data-seconds="5025"')
    end

    it 'does not match colons inside URLs as timestamps' do
      out = fmt.call('Source: https://example.com/api/v1:2 explained')
      # The 1:2 inside the URL should not be wrapped as a timestamp
      expect(out.scan('class="yt-timestamp"').length).to eq(0)
    end
  end

  describe 'hashtags' do
    it 'links #word to the YouTube search URL' do
      out = fmt.call('Tagged: #Wildlife #DavidAttenborough')
      expect(out).to include('class="yt-hashtag"')
      expect(out).to include('href="https://www.youtube.com/results?search_query=%23Wildlife"')
      expect(out).to include('href="https://www.youtube.com/results?search_query=%23DavidAttenborough"')
    end

    it 'does not match # in the middle of words (only after whitespace)' do
      out = fmt.call('See issue#123 for details')
      expect(out).not_to include('yt-hashtag')
    end
  end

  describe 'combined input (the BBC Earth fixture from prod)' do
    let(:fixture) do
      <<~DESC
        Join us in celebrating Sir David Attenborough's 100th birthday.

        Subscribe: http://bit.ly/BBCEarthSub
        Newsletter https://www.bbcearth.com/newsletter

        #Wildlife #WildlifeDocumentary

        0:00 Intro
        1:23 First scene
      DESC
    end

    it 'renders URLs, timestamps, and hashtags all in one pass' do
      out = fmt.call(fixture)
      expect(out).to include('<a href="http://bit.ly/BBCEarthSub"')
      expect(out).to include('<a href="https://www.bbcearth.com/newsletter"')
      expect(out).to include('class="yt-hashtag"')
      expect(out).to include('data-seconds="0"')
      expect(out).to include('data-seconds="83"')
    end
  end
end
