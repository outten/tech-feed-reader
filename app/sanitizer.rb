require 'loofah'

# Strips dangerous tags / attributes from feed-supplied HTML before we
# render it. Whitelist mode (loofah's :prune) — anything not on the
# safe list (paragraphs, links, lists, code blocks, images, etc.) is
# removed entirely. Critically: <script>, <iframe>, and on-* event
# handlers go.
#
# After the prune pass we run ExternalLinkScrubber, which annotates
# every <a href="http(s)://..."> with target="_blank" + rel=
# "noopener noreferrer". Citations and source links inside the article
# body open in a new tab so the reader stays in the reading view, and
# the rel attributes block reverse-tabnabbing + referrer leakage.
# Same-document and relative links are left alone — those are
# intra-article anchors, not external citations.
#
# Two outputs:
#   sanitize_html(html) — safe HTML for the reading view
#   text_only(html)     — plain text for FTS5 indexing + snippets
module Sanitizer
  module_function

  def sanitize_html(html)
    return '' if html.to_s.empty?
    fragment = Loofah.fragment(html.to_s).scrub!(:prune)
    fragment.scrub!(ExternalLinkScrubber.new)
    fragment.to_s
  end

  def text_only(html)
    return '' if html.to_s.empty?
    Loofah.fragment(html.to_s).text(encode_special_chars: false).strip
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
