require 'uri'
require_relative 'http_client'
require_relative '../logger'

# STUFF #30 — resolve a YouTube channel reference (in any of the
# common shapes a user might paste) to the canonical RSS feed URL
# the rest of the app uses (https://www.youtube.com/feeds/videos.xml
# ?channel_id=UC…). Supports:
#
#   * @PBSNewsHour                              # bare @handle
#   * PBSNewsHour                               # bare handle, no @
#   * https://www.youtube.com/@PBSNewsHour      # handle URL
#   * https://www.youtube.com/c/PBSNewsHour     # legacy /c/ custom URL
#   * https://www.youtube.com/user/PBSNewsHour  # legacy /user/ URL
#   * https://www.youtube.com/channel/UC…       # direct channel URL
#   * https://www.youtube.com/feeds/videos.xml?channel_id=UC…  # canonical
#
# Direct UC-id paths skip the channel-page scrape and go straight to
# the feed XML (one HTTP request) to validate + grab the title.
# Handle / legacy paths scrape the channel page HTML for the
# `"channelId":"UC…"` token YouTube embeds in its frontend JSON;
# that token has been stable for years and is what every third-party
# YouTube-to-RSS tool uses.
#
# No API key required. Used by POST /youtube/subscribe-bulk to let a
# user paste a list of handles on /youtube and subscribe in one go.
module Providers
  module YouTubeChannelResolver
    FEED_URL_PREFIX = 'https://www.youtube.com/feeds/videos.xml?channel_id='.freeze
    CHANNEL_PAGE    = 'https://www.youtube.com'.freeze

    CHANNEL_ID_RX        = /UC[A-Za-z0-9_-]{20,30}/
    JSON_CHANNEL_ID_RX   = /"channelId":"(UC[A-Za-z0-9_-]{20,30})"/
    CANONICAL_HREF_RX    = %r{<link\s+rel="canonical"\s+href="https?://www\.youtube\.com/channel/(UC[A-Za-z0-9_-]{20,30})"}
    OG_TITLE_RX          = /<meta\s+property="og:title"\s+content="([^"]+)"/
    FEED_TITLE_RX        = %r{<title>([^<]+)</title>}

    # Result envelope — `status` is the only field every variant carries.
    # On :ok, channel_id / title / feed_url are populated; on :not_found
    # or :error, `error` holds a human-readable explanation.
    Result = Struct.new(:status, :channel_id, :title, :feed_url, :error,
                        keyword_init: true)

    module_function

    # Resolve one user-supplied string. Returns a Result; never raises.
    # `http_get` is dependency-injected for tests so the suite never
    # touches the real network.
    def resolve(input, http_get: nil)
      input  = input.to_s.strip
      return error("blank input") if input.empty?

      http = http_get || method(:default_http_get)

      # Fast path 1: already-canonical feed URL.
      if (m = input.match(%r{youtube\.com/feeds/videos\.xml\?channel_id=(UC[A-Za-z0-9_-]+)}))
        return resolve_by_channel_id(m[1], http)
      end

      # Fast path 2: /channel/UC… URL or bare UC… id.
      if (m = input.match(%r{youtube\.com/channel/(UC[A-Za-z0-9_-]+)}))
        return resolve_by_channel_id(m[1], http)
      end
      if input.match?(/\AUC[A-Za-z0-9_-]{20,30}\z/)
        return resolve_by_channel_id(input, http)
      end

      # Slow path: anything else has to go through a channel-page scrape.
      page_url = page_url_for(input)
      return error("not a recognizable YouTube reference") unless page_url

      response = safe_get(http, page_url)
      return error("HTTP #{response.code} from #{page_url}", :not_found) if response.code.to_s == '404'
      return error("HTTP #{response.code} from #{page_url}") unless response.code.to_s == '200'

      body = response.body.to_s
      channel_id = extract_channel_id_from_html(body)
      return error("channel page did not expose a channelId — handle may not exist", :not_found) unless channel_id

      title = extract_title_from_html(body) || channel_id
      feed_url = FEED_URL_PREFIX + channel_id
      ok(channel_id: channel_id, title: title, feed_url: feed_url)
    rescue StandardError => e
      AppLogger.error('youtube_resolver', status: :error, input: input,
                                          class: e.class.name, message: e.message)
      error("#{e.class.name}: #{e.message}")
    end

    # ---- internals ------------------------------------------------------

    # Build the channel page URL for a handle-style input. Returns nil
    # for inputs we can't shape into a real page URL (e.g. arbitrary
    # http URLs that aren't on youtube.com).
    def page_url_for(input)
      # Bare @handle or bare handle without @.
      if (m = input.match(/\A@?([A-Za-z0-9_.-]+)\z/))
        return "#{CHANNEL_PAGE}/@#{m[1]}"
      end

      uri = URI.parse(input) rescue nil
      return nil unless uri && uri.host && uri.host.include?('youtube.com')

      path = uri.path.to_s
      case path
      when %r{\A/@[A-Za-z0-9_.-]+\z}                          then CHANNEL_PAGE + path
      when %r{\A/c/([A-Za-z0-9_.-]+)\z},
           %r{\A/user/([A-Za-z0-9_.-]+)\z}                    then CHANNEL_PAGE + path
      else
        nil
      end
    end

    # Resolve when we already know the UC… channel id. Fetches the
    # feed XML to validate it exists + grab the channel title.
    def resolve_by_channel_id(channel_id, http)
      feed_url = FEED_URL_PREFIX + channel_id
      response = safe_get(http, feed_url)
      return error("HTTP #{response.code} fetching feed", :not_found) if response.code.to_s == '404'
      return error("HTTP #{response.code} fetching feed") unless response.code.to_s == '200'

      title = extract_title_from_feed_xml(response.body.to_s) || channel_id
      ok(channel_id: channel_id, title: title, feed_url: feed_url)
    end

    def extract_channel_id_from_html(body)
      m = body.match(JSON_CHANNEL_ID_RX) || body.match(CANONICAL_HREF_RX)
      m && m[1]
    end

    def extract_title_from_html(body)
      m = body.match(OG_TITLE_RX)
      return nil unless m
      decode_html_entities(m[1].strip)
    end

    def extract_title_from_feed_xml(body)
      m = body.match(FEED_TITLE_RX)
      return nil unless m
      decode_html_entities(m[1].strip)
    end

    # Tiny entity decoder — channel titles regularly contain &amp; and
    # the occasional smart-quote escape. Full HTML decoding pulls in
    # CGI/htmlentities for marginal value; this covers the cases that
    # appear in real YouTube titles.
    def decode_html_entities(s)
      s.gsub('&amp;', '&')
       .gsub('&lt;',  '<')
       .gsub('&gt;',  '>')
       .gsub('&quot;', '"')
       .gsub('&#39;', "'")
       .gsub('&apos;', "'")
    end

    def safe_get(http, url)
      http.call(url)
    end

    def default_http_get(url)
      Providers::HttpClient.get(url)
    end

    def ok(channel_id:, title:, feed_url:)
      Result.new(status: :ok, channel_id: channel_id, title: title, feed_url: feed_url)
    end

    def error(message, status = :error)
      Result.new(status: status, error: message)
    end
  end
end
