require 'feedjira'
require 'digest'
require_relative 'sanitizer'

# Wraps feedjira so the rest of the app sees one normalised shape no
# matter whether the source is RSS 2.0, RSS 1.0, or Atom. Forces UTF-8
# on parse and scrubs invalid bytes (gotcha #1 in AGENTS.md — feeds in
# the wild are full of mis-declared encodings).
#
# Output shape:
#   {
#     title:   String|nil,                     # feed-level title
#     entries: [
#       {
#         uid:           String,               # SHA1(feed_url + entry.url)[0,12]
#         title:         String,
#         url:           String,
#         author:        String|nil,
#         published_at:  String|nil (ISO8601),
#         content_html:  String (sanitized),
#         content_text:  String (plain)
#       },
#       ...
#     ]
#   }
module FeedParser
  module_function

  def parse(body, feed_url:)
    body = body.to_s.dup.force_encoding(Encoding::UTF_8)
    body.scrub!('?')
    feed = Feedjira.parse(body)
    {
      title:   feed.title,
      entries: feed.entries.map { |e| normalise(e, feed_url: feed_url) }
    }
  end

  def uid_for(feed_url, entry_url)
    Digest::SHA1.hexdigest("#{feed_url}\0#{entry_url}")[0, 12]
  end

  class << self
    private

    def normalise(entry, feed_url:)
      url  = entry.url.to_s.strip
      url  = entry.entry_id.to_s if url.empty?
      raw  = entry.content || entry.summary || ''

      {
        uid:          uid_for(feed_url, url),
        title:        entry.title.to_s,
        url:          url,
        author:       (entry.respond_to?(:author) ? entry.author : nil),
        published_at: entry.published&.utc&.iso8601,
        content_html: Sanitizer.sanitize_html(raw),
        content_text: Sanitizer.text_only(raw)
      }
    end
  end
end
