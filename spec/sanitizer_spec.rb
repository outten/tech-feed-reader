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
