require_relative '../spec_helper'
require_relative '../../app/providers/http_client'

RSpec.describe Providers::HttpClient do
  describe 'test-env guard' do
    it 'raises on any unstubbed call so accidents fail loudly' do
      ENV.delete('ALLOW_HTTP')
      expect {
        Providers::HttpClient.get('https://example.com/')
      }.to raise_error(/HTTP calls disabled in test env/)
    end
  end

  describe '.get' do
    around(:each) do |ex|
      ENV['ALLOW_HTTP'] = '1'
      ex.run
    ensure
      ENV.delete('ALLOW_HTTP')
    end

    it 'rejects non-http(s) URLs' do
      expect {
        Providers::HttpClient.get('file:///etc/passwd')
      }.to raise_error(ArgumentError, /Unsupported URL scheme/)
    end

    it 'sets User-Agent + passes conditional-GET headers' do
      captured_req = nil
      response     = instance_double(Net::HTTPSuccess, code: '200', body: '<rss/>')

      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:start) do |&blk|
        result = blk.call(http)
        result
      end
      allow(http).to receive(:request) do |req|
        captured_req = req
        response
      end

      Providers::HttpClient.get(
        'https://example.com/feed',
        headers: {
          'If-Modified-Since' => 'Fri, 02 May 2026 12:00:00 GMT',
          'If-None-Match'     => 'W/"abc123"'
        }
      )

      expect(captured_req['User-Agent']).to start_with('tech-feed-reader/')
      expect(captured_req['If-Modified-Since']).to eq('Fri, 02 May 2026 12:00:00 GMT')
      expect(captured_req['If-None-Match']).to    eq('W/"abc123"')
    end

    it 'drops nil / empty conditional-GET headers' do
      captured_req = nil
      response     = instance_double(Net::HTTPSuccess, code: '200', body: '<rss/>')

      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:start) { |&blk| blk.call(http) }
      allow(http).to receive(:request) { |req| captured_req = req; response }

      Providers::HttpClient.get(
        'https://example.com/feed',
        headers: { 'If-Modified-Since' => nil, 'If-None-Match' => '' }
      )

      expect(captured_req['If-Modified-Since']).to be_nil
      expect(captured_req['If-None-Match']).to    be_nil
    end

    it 'retries transient transport errors and gives up after MAX_RETRIES' do
      attempts = 0
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:start) do |&_blk|
        attempts += 1
        raise Net::ReadTimeout
      end

      expect {
        Providers::HttpClient.get('https://example.com/feed')
      }.to raise_error(Net::ReadTimeout)

      expect(attempts).to eq(Providers::HttpClient::MAX_RETRIES + 1)
    end

    it 'does not retry on 4xx / 5xx (those return as-is)' do
      response = instance_double(Net::HTTPNotFound, code: '404', body: 'nope')
      http     = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:start) { |&blk| blk.call(http) }
      allow(http).to receive(:request).once.and_return(response)

      out = Providers::HttpClient.get('https://example.com/feed')
      expect(out.code).to eq('404')
    end
  end
end
