require_relative '../spec_helper'
require_relative '../../app/providers/readability'

RSpec.describe Providers::Readability do
  describe '.teaser?' do
    it 'flags short content_text' do
      expect(Providers::Readability.teaser?('Comments')).to be(true)
      expect(Providers::Readability.teaser?('Read more')).to be(true)
      expect(Providers::Readability.teaser?('continue reading')).to be(true)
    end

    it 'flags any text under 300 chars' do
      expect(Providers::Readability.teaser?('a' * 50)).to be(true)
      expect(Providers::Readability.teaser?('a' * 299)).to be(true)
    end

    it 'does not flag substantial bodies' do
      expect(Providers::Readability.teaser?('a' * 600)).to be(false)
    end

    it 'handles nil / empty' do
      expect(Providers::Readability.teaser?(nil)).to be(true)
      expect(Providers::Readability.teaser?('')).to be(true)
    end
  end

  describe '.extract' do
    let(:article_html) { File.read(File.expand_path('../fixtures/article_page.html', __dir__)) }
    let(:density_html) { File.read(File.expand_path('../fixtures/density_page.html', __dir__)) }

    def stub_get(body:, code: 200)
      response = instance_double(Net::HTTPResponse, code: code.to_s, body: body)
      allow(response).to receive(:[]) { |_| nil }
      allow(Providers::HttpClient).to receive(:get).and_return(response)
    end

    it 'returns the <article> body when available, sanitized' do
      stub_get(body: article_html)
      result = Providers::Readability.extract('https://example.com/post')
      expect(result).not_to be_nil
      expect(result[:text]).to include('TUIs are back')
      expect(result[:text]).to include('lazygit')
      expect(result[:html]).not_to include('<script')
      expect(result[:html]).not_to include('console.log')
    end

    it 'strips clutter (nav, footer, aside, script) before extracting' do
      stub_get(body: article_html)
      result = Providers::Readability.extract('https://example.com/post')
      expect(result[:text]).not_to include('Related')
      expect(result[:text]).not_to include('Another post')
    end

    it 'falls back to density-based picking when no known selector matches' do
      stub_get(body: density_html)
      result = Providers::Readability.extract('https://example.com/post')
      expect(result).not_to be_nil
      expect(result[:text]).to include('Lorem ipsum')
      expect(result[:text]).not_to include('scattered intro')
    end

    it 'returns nil on a non-2xx response' do
      stub_get(body: '<p>nope</p>', code: 404)
      expect(Providers::Readability.extract('https://example.com/post')).to be_nil
    end

    it 'returns nil when the page has no extractable content' do
      stub_get(body: '<html><body><p>too short</p></body></html>')
      expect(Providers::Readability.extract('https://example.com/post')).to be_nil
    end

    it 'returns nil on empty / missing URL' do
      expect(Providers::Readability.extract(nil)).to be_nil
      expect(Providers::Readability.extract('')).to be_nil
    end

    it 'returns nil instead of raising on transport errors' do
      allow(Providers::HttpClient).to receive(:get).and_raise(Net::ReadTimeout)
      expect(Providers::Readability.extract('https://example.com/post')).to be_nil
    end
  end
end
