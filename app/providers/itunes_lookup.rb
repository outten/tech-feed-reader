require 'json'
require_relative 'http_client'
require_relative '../logger'

# Cosmetics 6 — fall-back podcast cover-art lookup via the public
# iTunes Search API. Some publishers (Vox-published Ezra Klein
# included) don't expose <itunes:image> or <image><url> in their
# RSS, but every podcast in Apple Podcasts has artwork. This module
# queries `itunes.apple.com/search` by show title and returns the
# best artwork URL.
#
# Used by:
#   - scripts/backfill_podcast_images.rb (`make backfill-podcast-images`)
# Could be wired into `make refresh-feeds` later if we want
# eventually-consistent art for new feeds, but for v1 a one-shot
# manual sweep is enough.
#
# No API key required. Rate-limited to ~20 req/min by Apple — fine
# for a dozen-feed backfill, would need throttling for anything
# bigger.
module Providers
  module ITunesLookup
    SEARCH_URL = 'https://itunes.apple.com/search'.freeze
    LOOKUP_URL = 'https://itunes.apple.com/lookup'.freeze

    Result = Struct.new(:status, :artwork_url, :collection_name, :raw_match, :error,
                        keyword_init: true)

    # Used by Apple-Podcasts URL auto-resolution in POST /feeds. Stripped
    # to the fields needed by feed submission (feed URL + display name +
    # artwork) so callers don't have to dig through raw_match.
    LookupByIdResult = Struct.new(:status, :feed_url, :collection_name,
                                  :artwork_url, :error,
                                  keyword_init: true)

    module_function

    # Look up a podcast by title. Returns a Result whose status is
    # :ok (with artwork_url populated), :not_found (no matches), or
    # :error (HTTP / JSON failure). Never raises.
    #
    # Strategy: query iTunes for `term=<title>` with media=podcast +
    # entity=podcast, score the top results by title-similarity, return
    # the best match's artworkUrl600 (with artworkUrl100 as a fallback).
    def find_artwork(title, http_get: nil)
      title = title.to_s.strip
      return Result.new(status: :not_found, error: 'empty title') if title.empty?

      params = URI.encode_www_form(
        term:     title,
        media:    'podcast',
        entity:   'podcast',
        limit:    5
      )
      url = "#{SEARCH_URL}?#{params}"

      AppLogger.debug('itunes_lookup_start', title: title)
      response = (http_get || method(:default_http_get)).call(url)
      unless response.code.to_s == '200'
        AppLogger.warn('itunes_lookup', status: :error, http_status: response.code, title: title)
        return Result.new(status: :error, error: "HTTP #{response.code}")
      end

      data = JSON.parse(response.body)
      results = Array(data['results'])
      best = pick_best_match(title, results)
      if best.nil?
        AppLogger.info('itunes_lookup', status: :not_found, title: title, candidate_count: results.length)
        return Result.new(status: :not_found, raw_match: nil)
      end

      artwork = best['artworkUrl600'].to_s.strip
      artwork = best['artworkUrl100'].to_s.strip if artwork.empty?
      if artwork.empty?
        return Result.new(status: :not_found, raw_match: best, error: 'no artwork URL on match')
      end

      AppLogger.info('itunes_lookup', status: :ok, title: title,
                                       collection: best['collectionName'])
      Result.new(status: :ok, artwork_url: artwork,
                              collection_name: best['collectionName'],
                              raw_match: best)
    rescue JSON::ParserError => e
      AppLogger.error('itunes_lookup', status: :error, class: e.class.name, message: e.message)
      Result.new(status: :error, error: "JSON parse: #{e.message}")
    rescue StandardError => e
      AppLogger.error('itunes_lookup', status: :error, class: e.class.name, message: e.message)
      Result.new(status: :error, error: "#{e.class.name}: #{e.message}")
    end

    # STUFF.md follow-up — users sometimes paste an Apple Podcasts
    # web URL (podcasts.apple.com/.../idNNN) into POST /feeds instead
    # of the actual RSS. The page is HTML so the feed parser silently
    # imports zero entries. iTunes' /lookup endpoint resolves a podcast
    # ID to its real feedUrl in one HTTP hit, no API key needed.
    #
    # Returns a LookupByIdResult:
    #   :ok        — feed_url + collection_name + artwork_url populated
    #   :not_found — id valid but no results (deleted show, wrong region)
    #   :error     — HTTP or JSON failure
    def lookup_by_id(podcast_id, http_get: nil)
      podcast_id = podcast_id.to_s.strip
      return LookupByIdResult.new(status: :not_found, error: 'empty id') if podcast_id.empty?

      url = "#{LOOKUP_URL}?id=#{podcast_id}&entity=podcast"
      AppLogger.debug('itunes_lookup_by_id_start', podcast_id: podcast_id)
      response = (http_get || method(:default_http_get)).call(url)
      unless response.code.to_s == '200'
        AppLogger.warn('itunes_lookup_by_id', status: :error, http_status: response.code, podcast_id: podcast_id)
        return LookupByIdResult.new(status: :error, error: "HTTP #{response.code}")
      end

      data = JSON.parse(response.body)
      results = Array(data['results'])
      match = results.first
      if match.nil?
        AppLogger.info('itunes_lookup_by_id', status: :not_found, podcast_id: podcast_id)
        return LookupByIdResult.new(status: :not_found)
      end

      feed_url = match['feedUrl'].to_s.strip
      if feed_url.empty?
        return LookupByIdResult.new(status: :not_found, error: 'no feedUrl on match')
      end

      artwork = match['artworkUrl600'].to_s.strip
      artwork = match['artworkUrl100'].to_s.strip if artwork.empty?

      AppLogger.info('itunes_lookup_by_id', status: :ok, podcast_id: podcast_id,
                                              collection: match['collectionName'])
      LookupByIdResult.new(status: :ok, feed_url: feed_url,
                                         collection_name: match['collectionName'],
                                         artwork_url: artwork.empty? ? nil : artwork)
    rescue JSON::ParserError => e
      AppLogger.error('itunes_lookup_by_id', status: :error, class: e.class.name, message: e.message)
      LookupByIdResult.new(status: :error, error: "JSON parse: #{e.message}")
    rescue StandardError => e
      AppLogger.error('itunes_lookup_by_id', status: :error, class: e.class.name, message: e.message)
      LookupByIdResult.new(status: :error, error: "#{e.class.name}: #{e.message}")
    end

    # Extract the numeric podcast ID from a podcasts.apple.com URL.
    # Pattern: …/id<digits> (Apple uses this in both legacy and current
    # URL formats). Returns nil for anything that isn't an Apple
    # Podcasts URL so callers can short-circuit cleanly.
    def apple_podcast_id_from_url(url)
      return nil unless url.to_s.include?('podcasts.apple.com')
      m = url.match(%r{/id(\d+)(?:[/?#]|\z)})
      m && m[1]
    end

    # Pick the candidate whose collectionName best matches the query.
    # Exact case-insensitive match wins; otherwise prefer one that
    # contains the query as a substring; otherwise the first result.
    def pick_best_match(title, results)
      return nil if results.empty?
      lower = title.downcase
      exact = results.find { |r| r['collectionName'].to_s.downcase == lower }
      return exact if exact
      contains = results.find { |r| r['collectionName'].to_s.downcase.include?(lower) }
      contains || results.first
    end

    class << self
      private

      def default_http_get(url)
        Providers::HttpClient.get(url)
      end
    end
  end
end
