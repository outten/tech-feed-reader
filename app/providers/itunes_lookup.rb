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

    Result = Struct.new(:status, :artwork_url, :collection_name, :raw_match, :error,
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
