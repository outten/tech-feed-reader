require_relative 'spec_helper'
require_relative '../app/sanitizer'

RSpec.describe Sanitizer do
  describe '.sanitize_html' do
    it 'strips <script> blocks' do
      html = '<p>Hi</p><script>alert("xss")</script>'
      out  = Sanitizer.sanitize_html(html)
      expect(out).to include('<p>Hi</p>')
      expect(out).not_to include('<script>')
      expect(out).not_to include('alert')
    end

    it 'strips <iframe> blocks' do
      html = '<p>Body</p><iframe src="https://evil.example.com"></iframe>'
      out  = Sanitizer.sanitize_html(html)
      expect(out).not_to include('<iframe')
      expect(out).to include('<p>Body</p>')
    end

    it 'strips on-* event handlers' do
      html = '<a href="https://example.com" onclick="bad()">click</a>'
      out  = Sanitizer.sanitize_html(html)
      expect(out).not_to include('onclick')
      expect(out).to include('href="https://example.com"')
    end

    it 'preserves safe tags (links, paragraphs, lists, code)' do
      html = '<p>Para</p><ul><li>one</li></ul><pre><code>x = 1</code></pre>'
      out  = Sanitizer.sanitize_html(html)
      expect(out).to include('<p>Para</p>')
      expect(out).to include('<li>one</li>')
      expect(out).to include('<code>x = 1</code>')
    end

    it 'opens external citations in a new tab with safe rel attributes' do
      html = '<p>See <a href="https://example.com/source">the source</a>.</p>'
      out  = Sanitizer.sanitize_html(html)
      expect(out).to include('target="_blank"')
      expect(out).to include('rel="noopener noreferrer"')
      expect(out).to include('href="https://example.com/source"')
    end

    it 'leaves relative / fragment links alone when no base_url is given' do
      html = '<p>See <a href="/local/page">here</a> and <a href="#section">section</a>.</p>'
      out  = Sanitizer.sanitize_html(html)
      expect(out).not_to include('target="_blank"')
      expect(out).to include('href="/local/page"')
      expect(out).to include('href="#section"')
    end

    # STUFF #61 — link absolutization
    describe 'with base_url:' do
      let(:base) { 'https://example.com/news/2026/05/22/article.html' }

      it 'rewrites root-relative <a href> to absolute' do
        html = '<p><a href="/news/foo">foo</a></p>'
        out  = Sanitizer.sanitize_html(html, base_url: base)
        expect(out).to include('href="https://example.com/news/foo"')
        # And the now-absolute link gets target=_blank
        expect(out).to include('target="_blank"')
      end

      it 'rewrites path-relative <a href> against the base URL' do
        html = '<a href="related.html">x</a>'
        out  = Sanitizer.sanitize_html(html, base_url: base)
        expect(out).to include('href="https://example.com/news/2026/05/22/related.html"')
      end

      it 'rewrites protocol-relative <a href> using the base URL\'s scheme' do
        html = '<a href="//other.com/x">x</a>'
        out  = Sanitizer.sanitize_html(html, base_url: base)
        expect(out).to include('href="https://other.com/x"')
      end

      it 'leaves already-absolute http(s) URLs untouched' do
        html = '<a href="http://other.com/page">x</a>'
        out  = Sanitizer.sanitize_html(html, base_url: base)
        expect(out).to include('href="http://other.com/page"')
      end

      it 'leaves anchor / mailto / tel links alone' do
        html = <<~HTML
          <a href="#section">top</a>
          <a href="mailto:foo@example.com">mail</a>
          <a href="tel:+15551234">phone</a>
        HTML
        out = Sanitizer.sanitize_html(html, base_url: base)
        expect(out).to include('href="#section"')
        expect(out).to include('href="mailto:foo@example.com"')
        expect(out).to include('href="tel:+15551234"')
      end

      it 'rewrites <img src> the same way as <a href>' do
        html = '<img src="/img/photo.jpg" alt="">'
        out  = Sanitizer.sanitize_html(html, base_url: base)
        expect(out).to include('src="https://example.com/img/photo.jpg"')
      end

      it 'tolerates malformed URIs without raising' do
        html = '<a href="http://[invalid">bad</a> <a href="/ok">ok</a>'
        expect {
          out = Sanitizer.sanitize_html(html, base_url: base)
          # The /ok link should still get absolutized despite the bad one
          expect(out).to include('href="https://example.com/ok"')
        }.not_to raise_error
      end

      it 'tolerates a non-absolute base_url (opaque GUID) without raising' do
        # Older podcast feeds sometimes use the entry_id as the url
        # fallback; that GUID isn't a valid URI base. URI.join raises
        # URI::BadURIError on "both URI are relative" — we catch it.
        html = '<a href="/foo">x</a>'
        expect {
          Sanitizer.sanitize_html(html, base_url: 'urn:uuid:abc-123')
        }.not_to raise_error
      end

      it 'no-ops when base_url is nil or empty' do
        html = '<a href="/x">x</a>'
        out_nil   = Sanitizer.sanitize_html(html, base_url: nil)
        out_empty = Sanitizer.sanitize_html(html, base_url: '')
        expect(out_nil).to include('href="/x"')
        expect(out_empty).to include('href="/x"')
      end

      it 'is idempotent — re-running on already-absolutized HTML is a no-op' do
        html  = '<a href="/news/x">x</a>'
        once  = Sanitizer.sanitize_html(html, base_url: base)
        twice = Sanitizer.sanitize_html(once, base_url: base)
        expect(twice).to eq(once)
      end
    end

    it 'tolerates anchors with no href attribute' do
      html = '<p>Bare <a>anchor</a> with no href.</p>'
      expect { Sanitizer.sanitize_html(html) }.not_to raise_error
    end

    it 'returns empty string for nil / empty input' do
      expect(Sanitizer.sanitize_html(nil)).to eq('')
      expect(Sanitizer.sanitize_html('')).to eq('')
    end
  end

  describe '.text_only' do
    it 'strips tags and returns plain text' do
      html = '<p>Hello <strong>world</strong>.</p>'
      expect(Sanitizer.text_only(html)).to eq('Hello world.')
    end

    it 'returns empty string for nil / empty input' do
      expect(Sanitizer.text_only(nil)).to eq('')
      expect(Sanitizer.text_only('')).to eq('')
    end

    it 'strips decoded inner tags so FTS text is clean (#104)' do
      html = '<td>&lt;strong&gt;Final cost&lt;/strong&gt;</td><td>&lt;strong&gt;$0&lt;/strong&gt;</td>'
      expect(Sanitizer.text_only(html)).to eq('Final cost$0')
    end
  end

  # STUFF #104 — some feeds double-encode inner HTML, so formatting tags
  # render as literal "<strong>" text. sanitize_html decodes recognised
  # encoded tags back to real ones, then re-prunes (so it stays XSS-safe).
  describe '.sanitize_html double-encoded markup (#104)' do
    it 'decodes double-encoded inline tags inside a real table cell' do
      html = '<table><tr><td>&lt;strong&gt;Final cost&lt;/strong&gt;</td><td>$0.12</td></tr></table>'
      out = Sanitizer.sanitize_html(html)
      expect(out).to include('<td><strong>Final cost</strong></td>')
      expect(out).not_to include('&lt;strong&gt;')
    end

    it 'decodes a double-encoded list' do
      out = Sanitizer.sanitize_html('<div>&lt;ul&gt;&lt;li&gt;5 points&lt;/li&gt;&lt;li&gt;2 points&lt;/li&gt;&lt;/ul&gt;</div>')
      expect(out).to include('<ul>')
      expect(out).to include('<li>5 points</li>')
    end

    it 'leaves genuine escaped < in prose alone (not a tag pattern)' do
      out = Sanitizer.sanitize_html('<p>For all x where 5 &lt; 10 and a &lt; b.</p>')
      expect(out).to include('5 &lt; 10')
      expect(out).to include('a &lt; b')
    end

    it 'does not decode a lone HTML example in prose (gate needs >= 2)' do
      out = Sanitizer.sanitize_html('<p>Use the &lt;p&gt; tag for paragraphs.</p>')
      expect(out).to include('&lt;p&gt;')
    end

    it 'never decodes <script> — a double-escaped script stays inert text' do
      out = Sanitizer.sanitize_html('<p>x</p>&lt;script&gt;alert(1)&lt;/script&gt;&lt;strong&gt;a&lt;/strong&gt;&lt;strong&gt;b&lt;/strong&gt;')
      expect(out).to include('&lt;script&gt;')          # still escaped, not executable
      expect(out).not_to include('<script')            # no real script tag
      expect(out).to include('<strong>a</strong>')     # the real formatting still decoded
    end

    it 'strips dangerous attrs from a decoded tag via the re-prune (no XSS)' do
      out = Sanitizer.sanitize_html('&lt;img src=x onerror=alert(1)&gt;&lt;strong&gt;a&lt;/strong&gt;')
      expect(out).to include('<img')
      expect(out).not_to include('onerror')
    end

    it 'leaves normal (already-decoded) content unchanged' do
      html = '<p><strong>Hello</strong> world</p>'
      expect(Sanitizer.sanitize_html(html)).to eq(html)
    end
  end

  # Some feeds leak serialized component / community data (HuggingFace
  # discussion threads, Condé Nast commerce widgets) into the article body
  # as visible JSON text. Strip those text nodes; keep real prose + code.
  describe '.sanitize_html serialized-data blobs' do
    let(:hf_blob) do
      '<p>Real intro about the model.</p>' \
      '<div><div>x\n","updatedAt":"2026-01-20T16:07:58.908Z","author":{"_id":"648a374f",' \
      '"fullname":"Sam"},"hidden":false,"reactions":[]</div></div>' \
      '<p>Real closing paragraph.</p>'
    end

    it 'removes a serialized community-JSON text node but keeps the prose' do
      out = Sanitizer.sanitize_html(hf_blob)
      expect(out).to include('Real intro about the model.')
      expect(out).to include('Real closing paragraph.')
      expect(out).not_to include('updatedAt')
      expect(out).not_to include('648a374f')
    end

    it 'also strips the blob from text_only so FTS text stays clean' do
      expect(Sanitizer.text_only(hf_blob)).not_to include('updatedAt')
      expect(Sanitizer.text_only(hf_blob)).to include('Real intro about the model.')
    end

    it 'preserves a legitimate JSON example inside <pre>/<code>' do
      html = '<p>The response:</p>' \
             '<pre>{"updatedAt":"2024","author":{"_id":"x"},"reactions":5}</pre>' \
             '<p>Done.</p>'
      out = Sanitizer.sanitize_html(html)
      expect(out).to include('"updatedAt"')
      expect(out).to include('"author"')
      expect(out).to include('Done.')
    end

    it 'preserves prose that casually names one of the fields' do
      html = '<p>The API returns an "author" object you can use for lookups.</p>'
      expect(Sanitizer.sanitize_html(html)).to include('The API returns an')
    end

    it 'does not strip a short snippet below the signature threshold' do
      # one signature key only — not a serialized blob
      html = '<p>Set "hidden": true to suppress it in the feed listing view today.</p>'
      expect(Sanitizer.sanitize_html(html)).to include('Set')
    end
  end

  describe 'SocialShareScrubber' do
    def clean(html) = Sanitizer.sanitize_html(html)

    it 'removes a Twitter/X share anchor' do
      html = '<p>Read this.</p><a href="https://twitter.com/intent/tweet?text=hi&amp;url=http://example.com">Tweet</a>'
      out  = clean(html)
      expect(out).to include('Read this.')
      expect(out).not_to include('twitter.com/intent')
      expect(out).not_to include('Tweet')
    end

    it 'removes an X.com share anchor' do
      html = '<a href="https://x.com/intent/tweet?url=http://example.com">Share on X</a>'
      expect(clean(html)).not_to include('x.com/intent')
    end

    it 'removes a Facebook sharer anchor' do
      html = '<p>Article.</p><a href="https://www.facebook.com/sharer/sharer.php?u=http://example.com">Share</a>'
      out  = clean(html)
      expect(out).to include('Article.')
      expect(out).not_to include('facebook.com/sharer')
    end

    it 'removes a LinkedIn share anchor' do
      html = '<a href="https://www.linkedin.com/shareArticle?url=http://example.com">LinkedIn</a>'
      expect(clean(html)).not_to include('linkedin.com/shareArticle')
    end

    it 'preserves a normal social profile link' do
      html = '<p>Follow us on <a href="https://twitter.com/example">@example</a>.</p>'
      out  = clean(html)
      expect(out).to include('twitter.com/example')
      expect(out).to include('@example')
    end

    it 'removes an AddThis container element' do
      html = '<p>Content.</p><div class="addthis_sharing_toolbox"><a href="#">Share</a></div>'
      out  = clean(html)
      expect(out).to include('Content.')
      expect(out).not_to include('addthis')
    end

    it 'removes a ShareThis container element' do
      html = '<p>Article.</p><div class="sharethis-inline-share-buttons"></div>'
      out  = clean(html)
      expect(out).to include('Article.')
      expect(out).not_to include('sharethis')
    end

    it 'removes a Jetpack sharedaddy block' do
      html = '<p>Post.</p><div class="sharedaddy sd-sharing-enabled"><a href="#">Share this</a></div>'
      out  = clean(html)
      expect(out).to include('Post.')
      expect(out).not_to include('sharedaddy')
    end

    it 'removes a button with share data-url attribute' do
      html = '<p>Body.</p><button class="social-share-btn" data-url="https://twitter.com/intent/tweet?url=http://example.com">Tweet</button>'
      out  = clean(html)
      expect(out).to include('Body.')
      expect(out).not_to include('twitter.com/intent')
    end

    it 'preserves an unrelated element whose class contains "share" as a substring' do
      html = '<div class="market-share-chart"><p>AAPL: 10%</p></div>'
      out  = clean(html)
      expect(out).to include('AAPL: 10%')
    end
  end
end
