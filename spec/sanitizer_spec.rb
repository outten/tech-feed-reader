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
  end
end
