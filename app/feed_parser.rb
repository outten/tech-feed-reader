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
#     title:     String|nil,                   # feed-level title
#     image_url: String|nil,                   # channel-level cover art
#                                              #   (itunes:image / RSS <image>)
#     entries: [
#       {
#         uid:                    String,      # SHA1(feed_url + entry.url)[0,12]
#         title:                  String,
#         url:                    String,
#         author:                 String|nil,
#         published_at:           String|nil (ISO8601),
#         content_html:           String (sanitized),
#         content_text:           String (plain),
#         image_url:              String|nil,  # per-entry thumbnail
#                                              #   (itunes:image / media:thumbnail / first <img>)
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
      title:     feed.title,
      image_url: extract_channel_image(feed),
      entries:   feed.entries.map { |e| normalise(e, feed_url: feed_url) }
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
        image_url:              extract_entry_image(entry, raw),
        audio_url:              audio_url,
        audio_mime_type:        audio_type,
        audio_duration_seconds: extract_duration(entry)
      }
    end

    # Channel-level cover art. iTunes RSS exposes both an <image> block
    # (parsed by feedjira into RSSImage with .url) and an <itunes:image>
    # href; either is fine. Plain RSS / Atom may have only <image> or
    # nothing — we return nil and the view degrades gracefully.
    def extract_channel_image(feed)
      itunes = feed.respond_to?(:itunes_image) ? feed.itunes_image.to_s.strip : ''
      return itunes unless itunes.empty?
      img = feed.respond_to?(:image) ? feed.image : nil
      return nil if img.nil?
      url = img.respond_to?(:url) ? img.url.to_s.strip : img.to_s.strip
      url.empty? ? nil : url
    end

    # Per-entry thumbnail / hero image. Falls through three sources in
    # priority order:
    #   1. <itunes:image>     — set on iTunes-podcast episodes
    #   2. entry.image        — feedjira's normalised accessor for
    #                           <media:thumbnail>, <media:content image/*>,
    #                           or Atom <link rel="enclosure" image/*>
    #   3. first <img> in the body HTML — last resort for blogs that
    #                           don't declare a thumbnail in the feed
    #                           but do embed images inline
    def extract_entry_image(entry, content_html)
      itunes = entry.respond_to?(:itunes_image) ? entry.itunes_image.to_s.strip : ''
      return itunes unless itunes.empty?
      direct = entry.respond_to?(:image) ? entry.image.to_s.strip : ''
      return direct unless direct.empty?
      first_img_src(content_html)
    end

    # Extract the src of the first <img> in an HTML fragment. Only
    # accepts http(s) absolute URLs — relative paths would 404 since
    # we render them outside the publisher's domain. Returns nil if no
    # qualifying image is present.
    def first_img_src(html)
      return nil if html.nil? || html.empty?
      match = html.to_s.match(/<img\b[^>]*\bsrc=(["'])(https?:[^"']+)\1/i)
      match && match[2]
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
