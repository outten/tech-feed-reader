require 'nokogiri'
require 'time'

# OPML 2.0 import + export for the feed list.
#
# Import: tolerant — finds every <outline> element with an `xmlUrl`
# attribute regardless of nesting (folder hierarchies are flattened
# since this app doesn't model folders). Outlines without xmlUrl are
# treated as containers and skipped.
#
# Export: a minimal but conformant OPML 2.0 document — head with title
# and dateCreated, then one <outline> per feed in body. Set type="rss"
# on every outline so other readers don't have to sniff.
#
# Both functions are pure — no I/O. The route handlers do the
# multipart upload / response writing.
module OPML
  module_function

  # Parse OPML XML and return [{url:, title:}] for every feed found.
  # Returns [] for blank / unparseable input rather than raising.
  def parse(xml)
    body = xml.to_s
    return [] if body.strip.empty?

    doc = Nokogiri::XML(body) { |c| c.recover }
    doc.css('outline[xmlUrl]').filter_map do |el|
      url   = el['xmlUrl'].to_s.strip
      title = (el['title'] || el['text']).to_s.strip
      next if url.empty?
      { url: url, title: title.empty? ? nil : title }
    end
  end

  # Build an OPML 2.0 document from FeedsStore-shaped rows
  # (hash with 'url' and 'title' keys). Returns the XML as a string.
  def build(feeds, head_title: 'tech-feed-reader feeds')
    builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
      xml.opml(version: '2.0') do
        xml.head do
          xml.title head_title
          xml.dateCreated Time.now.utc.rfc822
        end
        xml.body do
          feeds.each do |feed|
            label = feed['title'].to_s.empty? ? feed['url'].to_s : feed['title'].to_s
            xml.outline(
              type:   'rss',
              text:   label,
              title:  label,
              xmlUrl: feed['url'].to_s
            )
          end
        end
      end
    end
    builder.to_xml
  end
end
