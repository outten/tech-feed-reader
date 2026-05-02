require 'loofah'

# Strips dangerous tags / attributes from feed-supplied HTML before we
# render it. Whitelist mode (loofah's :prune) — anything not on the
# safe list (paragraphs, links, lists, code blocks, images, etc.) is
# removed entirely. Critically: <script>, <iframe>, and on-* event
# handlers go.
#
# Two outputs:
#   sanitize_html(html) — safe HTML for the reading view
#   text_only(html)     — plain text for FTS5 indexing + snippets
module Sanitizer
  module_function

  def sanitize_html(html)
    return '' if html.to_s.empty?
    Loofah.fragment(html.to_s).scrub!(:prune).to_s
  end

  def text_only(html)
    return '' if html.to_s.empty?
    Loofah.fragment(html.to_s).text(encode_special_chars: false).strip
  end
end
