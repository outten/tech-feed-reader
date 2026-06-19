require 'loofah'
require 'uri'
require 'cgi'

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
    cleaned  = decode_double_encoded_markup(html.to_s)
    fragment = Loofah.fragment(cleaned).scrub!(:prune)
    fragment.scrub!(LinkAbsolutizer.new(base_url)) if base_url && !base_url.to_s.empty?
    fragment.scrub!(ExternalLinkScrubber.new)
    fragment.to_s
  end

  def text_only(html)
    return '' if html.to_s.empty?
    Loofah.fragment(decode_double_encoded_markup(html.to_s)).text(encode_special_chars: false).strip
  end

  # STUFF #104 — some feeds double-encode inner HTML. The Points Guy ships
  #   <td>&lt;strong&gt;Final cost&lt;/strong&gt;</td>
  # so the cell renders the literal text "<strong>Final cost</strong>" instead
  # of bold; WordPress blocks and a JSON-data variant on HuggingFace do the
  # same. Decode the entity-encoded HTML *tags* back into real tags so they
  # render. Scoped two ways to stay safe:
  #   1. Only a recognised set of formatting/structure tags is decoded, so
  #      prose like "5 &lt; 10" or a one-off "&lt;p&gt;" code example is left
  #      untouched (the gate also requires at least two encoded tags).
  #   2. The caller re-prunes afterwards, so a double-escaped &lt;script&gt;
  #      decodes and is then stripped — this can't reintroduce XSS.
  SAFE_DECODE_TAGS = %w[
    p br hr div span a b i u s em strong small sub sup mark
    ul ol li dl dt dd blockquote pre code
    h1 h2 h3 h4 h5 h6
    table thead tbody tfoot tr td th caption colgroup col
    figure figcaption img picture source
  ].join('|').freeze

  # An entity-encoded tag: &lt;strong&gt;, &lt;/td&gt;, or
  # &lt;a href=&quot;...&quot;&gt; (attributes may carry encoded quotes, but
  # never a real < or >, which bounds the match to a single tag).
  ENCODED_TAG_RX = /&lt;\/?(?:#{SAFE_DECODE_TAGS})\b[^<>]{0,400}?&gt;/i

  def decode_double_encoded_markup(html)
    # Gate: needs at least two encoded tags so a lone HTML example in prose
    # isn't rewritten into a real tag.
    return html if html.scan(ENCODED_TAG_RX).length < 2
    html.gsub(ENCODED_TAG_RX) { |tag| CGI.unescapeHTML(tag) }
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
