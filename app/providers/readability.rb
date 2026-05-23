require 'nokogiri'
require_relative 'http_client'
require_relative '../sanitizer'

# Readability fallback for teaser feeds. Some publishers (Hacker News,
# Lobsters, /r/programming) ship RSS items whose <description> is just
# a comments link with no real article body. Without a fallback, those
# feeds land in the DB with content_text = "Comments" and the article
# view shows nothing.
#
# This provider GETs the entry's source URL and runs a simple
# Nokogiri-based extractor: try a list of common content selectors
# (<article>, <main>, .post-content, etc.); if none of them turn up
# enough text, fall back to a text-density heuristic that picks the
# block element with the most non-link text. The result is sanitized
# by the existing Sanitizer (loofah whitelist) so script / iframe /
# on-* handlers can't sneak in via a dodgy publisher page.
#
# Returns { html:, text: } on success, or nil on failure (network
# error, paywall, parse miss). Callers should treat nil as "no
# upgrade available; keep the original feed body".
module Providers
  module Readability
    # Selectors tried in order — first one with >= MIN_TEXT chars wins.
    CONTENT_SELECTORS = [
      'article',
      'main',
      '[role="main"]',
      '.entry-content',
      '.post-content',
      '.article-content',
      '.article-body',
      '.post-body',
      '.entry',
      '#content',
      '#main-content',
      '#main'
    ].freeze

    MIN_TEXT          = 400  # chars — below this, fall through
    DENSITY_MIN_TEXT  = 200  # chars to qualify as a candidate in the density fallback
    REQUEST_TIMEOUT   = 15   # seconds — readability isn't worth a long stall

    module_function

    # Returns { html: String, text: String } or nil.
    def extract(url)
      return nil if url.to_s.empty?

      response = Providers::HttpClient.get(url, timeout: REQUEST_TIMEOUT)
      return nil unless response.code.to_i.between?(200, 299)

      doc = Nokogiri::HTML.parse(response.body.to_s)
      strip_clutter!(doc)

      best = pick_by_selector(doc) || pick_by_density(doc)
      return nil unless best

      raw_html = best.inner_html.to_s
      # STUFF #61 — pass the source URL so relative links inside the
      # readability-extracted body get absolutized against the
      # publisher's domain (same as feed_parser.rb does for feed
      # entries).
      html     = Sanitizer.sanitize_html(raw_html, base_url: url)
      text     = Sanitizer.text_only(raw_html)
      return nil if text.length < DENSITY_MIN_TEXT
      { html: html, text: text }
    rescue StandardError
      # Don't let a bad publisher page crash the import. Return nil so
      # the caller falls through to whatever feed body was already there.
      nil
    end

    # Heuristic: short / placeholder content_text triggers a fallback
    # attempt. Lobsters / HN teasers are 5–20 chars ("Comments");
    # 300 chars is enough to spare blogs that legitimately ship short
    # bodies (e.g. status-update feeds) from an unnecessary network call.
    def teaser?(content_text)
      stripped = content_text.to_s.strip
      stripped.length < 300 || stripped.match?(/\A(comments?|read more|continue reading)\.?\z/i)
    end

    class << self
      private

      # Strip script / style / nav / footer / aside before scoring so they
      # don't poison the density heuristic.
      def strip_clutter!(doc)
        doc.css('script, style, noscript, nav, footer, aside, header, form').each(&:remove)
      end

      def pick_by_selector(doc)
        CONTENT_SELECTORS.each do |sel|
          el = doc.at_css(sel)
          next unless el
          return el if el.text.to_s.strip.length >= MIN_TEXT
        end
        nil
      end

      # Fallback: among block elements with a reasonable amount of text,
      # pick the one whose text-minus-link-text is largest. Filters out
      # nav menus and reference-link blocks where most of the text is
      # inside <a> tags.
      def pick_by_density(doc)
        best       = nil
        best_score = 0
        doc.css('div, section, article').each do |el|
          text = el.text.to_s
          next if text.length < DENSITY_MIN_TEXT

          link_chars = el.css('a').sum { |a| a.text.to_s.length }
          score      = text.length - link_chars
          if score > best_score
            best       = el
            best_score = score
          end
        end
        best
      end
    end
  end
end
