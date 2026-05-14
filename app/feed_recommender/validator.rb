require_relative '../feed_parser'
require_relative '../providers/http_client'
require_relative '../logger'
require_relative 'autodiscovery'

# STUFF #23 — validates a Claude-suggested feed URL by actually fetching
# it + trying to parse it as RSS/Atom/JSON Feed. Claude hallucinates
# URLs (404) and sometimes gives a real publication's URL that returns
# HTML, not RSS. The recommender only surfaces URLs that come back :ok.
#
# On :http_error or :not_a_feed, we make one fallback attempt via
# FeedRecommender::Autodiscovery — look at the page (or domain root)
# for `<link rel="alternate" type="application/rss+xml">` and try that
# URL. Recovers cases like `sporkful.com/feed/podcast/` (real podcast
# whose feed lives at a different path discoverable from the homepage).
#
# Designed for batch parallel use: #validate_many runs each URL on its
# own Thread, with a hard wall-clock cap, then collects whatever finished
# in time. The slowest single URL won't drag the whole batch past the
# cap.
module FeedRecommender
  module Validator
    DEFAULT_TIMEOUT_S       = 5     # per-URL HTTP timeout
    AUTODISCOVERY_TIMEOUT_S = 4     # per-probe budget for the fallback
    DEFAULT_BATCH_CAP_S     = 14    # max wall-clock across the whole batch
    MAX_BODY_BYTES          = 250_000  # generous cap; most feeds are <100KB

    Result = Struct.new(:url, :status, :title, :image_url, :entry_count,
                        :error, :discovered_via, keyword_init: true)

    module_function

    # Validate one URL. Returns Result with status one of:
    #   :ok          → looks like a real feed, has a title or ≥1 entries
    #   :http_error  → non-2xx response (and autodiscovery didn't recover)
    #   :not_a_feed  → 2xx but body didn't parse (and autodiscovery didn't help)
    #   :timeout     → request exceeded the timeout
    #   :error       → other connectivity / DNS / TLS failure
    def validate(url, timeout: DEFAULT_TIMEOUT_S)
      url = url.to_s.strip
      return Result.new(url: url, status: :error, error: 'blank url') if url.empty?

      primary = fetch_and_parse(url, timeout: timeout)
      return primary if primary.status == :ok

      # Fallback: try autodiscovery on the original URL (in case it's an
      # HTML page with a feed-link tag) or on the domain root. Only
      # triggers for the two failure modes autodiscovery can plausibly
      # recover; we don't retry on :timeout or :error since those signal
      # network-layer problems that the fallback would just inherit.
      if %i[http_error not_a_feed].include?(primary.status)
        discovered = Autodiscovery.discover(url, timeout: AUTODISCOVERY_TIMEOUT_S)
        if discovered && discovered != url
          AppLogger.info('feed_validate_autodiscovery',
                         source: url, discovered: discovered)
          secondary = fetch_and_parse(discovered, timeout: timeout)
          if secondary.status == :ok
            return Result.new(
              url:            discovered,
              status:         :ok,
              title:          secondary.title,
              image_url:      secondary.image_url,
              entry_count:    secondary.entry_count,
              discovered_via: url
            )
          end
        end
      end

      primary
    end

    # The original single-URL fetch + parse, factored out so the
    # autodiscovery fallback can call it on a second URL without
    # re-entering the autodiscovery branch (avoids accidental recursion).
    def fetch_and_parse(url, timeout:)
      response = Providers::HttpClient.get(url, timeout: timeout)
      code = response.code.to_i
      unless (200..299).cover?(code)
        return Result.new(url: url, status: :http_error, error: "HTTP #{code}")
      end

      body = response.body.to_s
      body = body.byteslice(0, MAX_BODY_BYTES) if body.bytesize > MAX_BODY_BYTES

      parsed = begin
        FeedParser.parse(body, feed_url: url)
      rescue Feedjira::NoParserAvailable, Feedjira::FeedjiraError => e
        return Result.new(url: url, status: :not_a_feed, error: e.message)
      end
      entries = Array(parsed[:entries])
      has_signal = !parsed[:title].to_s.strip.empty? || entries.any?
      return Result.new(url: url, status: :not_a_feed, error: 'body did not parse as a feed') unless has_signal

      Result.new(
        url:         url,
        status:      :ok,
        title:       parsed[:title].to_s.strip,
        image_url:   parsed[:image_url],
        entry_count: entries.length
      )
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
      Result.new(url: url, status: :timeout, error: e.message)
    rescue StandardError => e
      Result.new(url: url, status: :error, error: "#{e.class.name}: #{e.message}")
    end

    # Validate `urls` in parallel. Hard wall-clock cap so a single slow
    # feed doesn't gate everyone else. Returns an array of Result in
    # the same order as the input.
    def validate_many(urls, timeout: DEFAULT_TIMEOUT_S, batch_cap: DEFAULT_BATCH_CAP_S)
      return [] if urls.empty?

      threads = urls.map do |u|
        Thread.new { validate(u, timeout: timeout) }
      end
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + batch_cap

      threads.each_with_index.map do |t, i|
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        if remaining > 0 && t.join(remaining)
          t.value
        else
          t.kill
          AppLogger.warn('feed_validate_batch_timeout', url: urls[i])
          Result.new(url: urls[i], status: :timeout, error: 'batch cap exceeded')
        end
      end
    end
  end
end
