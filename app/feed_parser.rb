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
#         uid:                    String,      # SHA1(feed_url + entry.url)[0,12]
#         title:                  String,
#         url:                    String,
#         author:                 String|nil,
#         published_at:           String|nil (ISO8601),
#         content_html:           String (sanitized),
#         content_text:           String (plain),
#         audio_url:              String|nil,  # <enclosure ... type="audio/*">
#         audio_mime_type:        String|nil,
#         audio_duration_seconds: Integer|nil  # parsed from itunes:duration
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

      audio_url, audio_type = extract_audio(entry)

      {
        uid:                    uid_for(feed_url, url),
        title:                  entry.title.to_s,
        url:                    url,
        author:                 (entry.respond_to?(:author) ? entry.author : nil),
        published_at:           entry.published&.utc&.iso8601,
        content_html:           Sanitizer.sanitize_html(raw),
        content_text:           Sanitizer.text_only(raw),
        audio_url:              audio_url,
        audio_mime_type:        audio_type,
        audio_duration_seconds: extract_duration(entry)
      }
    end

    # Pick the first audio enclosure off the entry. feedjira exposes
    # `enclosure_url` + `enclosure_type` on RSS entries; iTunes-RSS uses
    # the same fields. Atom feeds emit `<link rel="enclosure">` which
    # feedjira normalises into the same accessors. Returns nil for both
    # if there's no audio enclosure.
    def extract_audio(entry)
      url  = entry.respond_to?(:enclosure_url)  ? entry.enclosure_url.to_s  : ''
      type = entry.respond_to?(:enclosure_type) ? entry.enclosure_type.to_s : ''
      return [nil, nil] if url.empty?
      return [nil, nil] unless type.empty? || type.start_with?('audio/')
      [url, type.empty? ? nil : type]
    end

    # iTunes <duration> ships as one of:
    #   "1234"       (raw seconds)
    #   "12:34"      (mm:ss)
    #   "1:23:45"    (hh:mm:ss)
    # Anything else returns nil so the player just shows the runtime
    # once the audio loads its own metadata.
    def extract_duration(entry)
      raw = entry.respond_to?(:itunes_duration) ? entry.itunes_duration.to_s : ''
      return nil if raw.empty?
      parts = raw.strip.split(':').map { |p| Integer(p, 10) rescue nil }
      return nil if parts.any?(&:nil?)
      case parts.length
      when 1 then parts[0]
      when 2 then parts[0] * 60 + parts[1]
      when 3 then parts[0] * 3600 + parts[1] * 60 + parts[2]
      end
    end
  end
end
