require_relative 'spec_helper'
require_relative '../app/opml'

RSpec.describe OPML do
  describe '.parse' do
    it 'returns [] for blank / whitespace input' do
      expect(OPML.parse(nil)).to eq([])
      expect(OPML.parse('')).to eq([])
      expect(OPML.parse('   ')).to eq([])
    end

    it 'extracts every outline with an xmlUrl, capturing title' do
      xml = <<~XML
        <?xml version="1.0"?>
        <opml version="2.0">
          <head><title>my feeds</title></head>
          <body>
            <outline type="rss" title="HN" xmlUrl="https://news.ycombinator.com/rss"/>
            <outline type="rss" text="Lobsters" xmlUrl="https://lobste.rs/rss"/>
          </body>
        </opml>
      XML
      result = OPML.parse(xml)
      expect(result).to contain_exactly(
        { url: 'https://news.ycombinator.com/rss', title: 'HN' },
        { url: 'https://lobste.rs/rss',            title: 'Lobsters' }
      )
    end

    it 'flattens folder hierarchies (nested outlines)' do
      xml = <<~XML
        <opml version="2.0"><body>
          <outline title="Tech">
            <outline type="rss" title="Ars" xmlUrl="https://arstechnica.com/feed/"/>
            <outline title="Sub-folder">
              <outline type="rss" title="Verge" xmlUrl="https://www.theverge.com/rss/index.xml"/>
            </outline>
          </outline>
          <outline title="Top-level container with no xmlUrl"/>
        </body></opml>
      XML
      urls = OPML.parse(xml).map { |f| f[:url] }
      expect(urls).to contain_exactly(
        'https://arstechnica.com/feed/',
        'https://www.theverge.com/rss/index.xml'
      )
    end

    it 'returns nil title when neither title nor text is set' do
      xml = '<opml><body><outline type="rss" xmlUrl="https://example.com/rss"/></body></opml>'
      expect(OPML.parse(xml).first[:title]).to be_nil
    end

    it 'tolerates malformed XML via libxml recover mode' do
      xml = '<opml><body><outline type="rss" title="Broken" xmlUrl="https://x.example.com/rss"</body></opml>'
      expect { OPML.parse(xml) }.not_to raise_error
    end
  end

  describe '.build' do
    it 'produces an OPML 2.0 document with one outline per feed' do
      feeds = [
        { 'url' => 'https://news.ycombinator.com/rss', 'title' => 'HN' },
        { 'url' => 'https://lobste.rs/rss',            'title' => 'Lobsters' }
      ]
      xml = OPML.build(feeds)
      doc = Nokogiri::XML(xml)
      expect(doc.at_css('opml')['version']).to eq('2.0')
      expect(doc.at_css('head > title').text).to include('feeds')
      outlines = doc.css('body > outline')
      expect(outlines.length).to eq(2)
      expect(outlines.map { |o| o['xmlUrl'] }).to contain_exactly(
        'https://news.ycombinator.com/rss', 'https://lobste.rs/rss'
      )
      expect(outlines.first['type']).to eq('rss')
    end

    it 'falls back to URL when title is blank' do
      xml = OPML.build([{ 'url' => 'https://example.com/rss', 'title' => '' }])
      out = Nokogiri::XML(xml).at_css('outline')
      expect(out['title']).to eq('https://example.com/rss')
      expect(out['text']).to  eq('https://example.com/rss')
    end
  end

  describe 'parse / build round-trip' do
    it 'preserves URL + title across export → import' do
      feeds = [
        { 'url' => 'https://example.com/feed.rss', 'title' => 'Example Tech' },
        { 'url' => 'https://other.example.com/atom.xml', 'title' => 'Other Place' }
      ]
      reparsed = OPML.parse(OPML.build(feeds))
      expect(reparsed).to contain_exactly(
        { url: 'https://example.com/feed.rss',     title: 'Example Tech' },
        { url: 'https://other.example.com/atom.xml', title: 'Other Place' }
      )
    end
  end
end
