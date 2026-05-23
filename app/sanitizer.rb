require 'loofah'
require 'uri'

# Strips dangerous tags / attributes from feed-supplied HTML before we
# render it. Whitelist mode (loofah's :prune) — anything not on the
# safe list (paragraphs, links, lists, code blocks, images, etc.) is
# removed entirely. Critically: <script>, <iframe>, and on-* event
# handlers go.
#
# STUFF #61 — When `base_url:` is supplied, LinkAbsolutizer rewrites
# every relative `<a href>` and `<img src>` to its absolute form using
# the article's own URL as the base. Publisher RSS often emits
# in-domain `/foo/bar`-style links that would otherwise resolve
# against feeder.tmoneystuff.com (→ 404). Runs BEFORE
# ExternalLinkScrubber so once-relative links also get target="_blank"
# once they're upgraded to absolute URLs.
#
# After the prune pass we run ExternalLinkScrubber, which annotates
# every <a href="http(s)://..."> with target="_blank" + rel=
# "noopener noreferrer". Citations and source links inside the article
# body open in a new tab so the reader stays in the reading view, and
# the rel attributes block reverse-tabnabbing + referrer leakage.
# Anchor (`#foo`) and protocol links (`mailto:`, `tel:`) are left
# alone — those aren't HTTP citations.
#
# Two outputs:
#   sanitize_html(html, base_url: nil) — safe HTML for the reading view
#   text_only(html)                    — plain text for FTS5 indexing
module Sanitizer
  module_function

  def sanitize_html(html, base_url: nil)
    return '' if html.to_s.empty?
    fragment = Loofah.fragment(html.to_s).scrub!(:prune)
    fragment.scrub!(LinkAbsolutizer.new(base_url)) if base_url && !base_url.to_s.empty?
    fragment.scrub!(ExternalLinkScrubber.new)
    fragment.to_s
  end

  def text_only(html)
    return '' if html.to_s.empty?
    Loofah.fragment(html.to_s).text(encode_special_chars: false).strip
  end

  # STUFF #61 — Rewrites relative `<a href>` and `<img src>` to
  # absolute URLs using the article's own URL as the base. Skips
  # already-absolute http(s) URLs + anchor/mailto/tel/data hrefs +
  # malformed URIs (defensive rescue around URI.join).
  class LinkAbsolutizer < Loofah::Scrubber
    SKIP_PREFIXES = %w[# mailto: tel: javascript: data:].freeze

    def initialize(base_url)
      @base       = base_url.to_s
      @direction  = :top_down
    end

    def scrub(node)
      if node.name == 'a' && node['href']
        node['href'] = absolutize(node['href'])
      elsif (node.name == 'img' || node.name == 'source') && node['src']
        node['src'] = absolutize(node['src'])
      end
      Loofah::Scrubber::CONTINUE
    end

    def absolutize(url)
      s = url.to_s.strip
      return s if s.empty?
      return s if s.start_with?(*SKIP_PREFIXES)
      return s if s.match?(%r{\Ahttps?://}i)
      URI.join(@base, s).to_s
    rescue URI::InvalidURIError, URI::BadURIError, ArgumentError
      url
    end
  end

  # Adds target="_blank" rel="noopener noreferrer" to every external
  # <a>. Top-down so we visit each anchor exactly once.
  class ExternalLinkScrubber < Loofah::Scrubber
    def initialize
      @direction = :top_down
    end

    def scrub(node)
      return Loofah::Scrubber::CONTINUE unless node.name == 'a'
      href = node['href'].to_s
      return Loofah::Scrubber::CONTINUE unless href.start_with?('http://', 'https://')
      node['target'] = '_blank'
      node['rel']    = 'noopener noreferrer'
      Loofah::Scrubber::CONTINUE
    end
  end
end
