require 'uri'
require 'nokogiri'
require_relative '../providers/http_client'

# STUFF #23 — feed autodiscovery fallback for the validator.
#
# When Claude suggests a URL that 404s or returns HTML instead of a feed,
# we try to recover by:
#   1. Fetching the HTML page (or the domain root)
#   2. Looking for <link rel="alternate" type="application/rss+xml" …>
#      or type="application/atom+xml" or type="application/json"
#   3. Returning the first href we find, absolute-ified against the page URL
#
# This recovers cases like `sporkful.com/feed/podcast/` (real podcast,
# wrong path — the homepage HTML has the actual feed URL in a <link>
# tag) and `thrillist.com/rss.xml` (the publication exists but its feed
# is at a different path — sometimes discoverable from the root).
module FeedRecommender
  module Autodiscovery
    FEED_LINK_TYPES = %w[
      application/rss+xml
      application/atom+xml
      application/feed+json
      application/json
    ].freeze

    module_function

    # Try to find a feed URL related to `source_url`. Returns a URL
    # string on success, nil on failure. Cheap by design — one HEAD-ish
    # GET, short timeout, no recursion.
    def discover(source_url, timeout: 4)
      uri = safe_uri(source_url)
      return nil unless uri

      # Two probes max: the source URL itself (in case it's an HTML page
      # with a <link> autodiscovery hint), then the domain root.
      candidates = [source_url, "#{uri.scheme}://#{uri.host}/"].uniq
      candidates.each do |probe|
        href = extract_feed_link_from(probe, timeout: timeout)
        return absolutize(href, probe) if href
      end
      nil
    end

    # Fetch the URL, parse as HTML, return the first feed-link href or nil.
    # Returns nil on any failure (non-2xx, parse error, no link found).
    def extract_feed_link_from(url, timeout: 4)
      response = Providers::HttpClient.get(url, timeout: timeout)
      return nil unless (200..299).cover?(response.code.to_i)
      body = response.body.to_s
      return nil if body.empty?

      doc = Nokogiri::HTML(body)
      link = doc.css('link[rel*="alternate"]').find do |node|
        type = node['type'].to_s.downcase
        href = node['href'].to_s
        FEED_LINK_TYPES.include?(type) && !href.empty?
      end
      link && link['href']
    rescue StandardError
      nil
    end

    def absolutize(href, base_url)
      return href if href.start_with?('http://', 'https://')
      base = URI(base_url)
      URI.join("#{base.scheme}://#{base.host}", href).to_s
    rescue StandardError
      nil
    end

    def safe_uri(url)
      u = URI(url)
      return nil unless u.host && %w[http https].include?(u.scheme)
      u
    rescue URI::InvalidURIError
      nil
    end
  end
end
