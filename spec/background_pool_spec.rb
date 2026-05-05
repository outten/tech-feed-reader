require_relative 'spec_helper'
require_relative '../app/background_pool'

RSpec.describe BackgroundPool do
  describe '.ids' do
    it 'returns the bundled DEFAULT_IDS when the pool table is empty' do
      expect(BackgroundPool.count).to eq(0)
      expect(BackgroundPool.ids).to eq(BackgroundPool::DEFAULT_IDS)
    end

    it 'returns stored picsum_ids when the pool is populated' do
      Database.connection.execute("INSERT INTO background_pool (picsum_id, author, unsplash_url) VALUES (?, ?, ?)",
                                  [501, 'Stored Photographer', 'https://unsplash.com/p/501'])
      Database.connection.execute("INSERT INTO background_pool (picsum_id, author, unsplash_url) VALUES (?, ?, ?)",
                                  [502, 'Other',                'https://unsplash.com/p/502'])
      expect(BackgroundPool.ids).to contain_exactly(501, 502)
    end
  end

  describe '.entries' do
    it 'returns full rows newest-first' do
      Database.connection.execute("INSERT INTO background_pool (picsum_id, author, unsplash_url, added_at) VALUES (?, ?, ?, ?)",
                                  [101, 'Older', 'https://example.com/o', '2026-05-01T10:00:00Z'])
      Database.connection.execute("INSERT INTO background_pool (picsum_id, author, unsplash_url, added_at) VALUES (?, ?, ?, ?)",
                                  [202, 'Newer', 'https://example.com/n', '2026-05-05T10:00:00Z'])

      ordered = BackgroundPool.entries
      expect(ordered.map { |r| r['picsum_id'] }).to eq([202, 101])
      expect(ordered.first['author']).to eq('Newer')
    end
  end

  describe '.refresh!' do
    let(:candidates) do
      [
        { id: '900', author: 'A', url: 'https://unsplash.com/p/a' },
        { id: '901', author: 'B', url: 'https://unsplash.com/p/b' },
        { id: '902', author: 'C', url: 'https://unsplash.com/p/c' }
      ]
    end

    it 'wipes the existing pool and inserts the requested count' do
      Database.connection.execute("INSERT INTO background_pool (picsum_id, author, unsplash_url) VALUES (?, ?, ?)",
                                  [777, 'Old Pool Entry', 'https://unsplash.com/old'])
      expect(BackgroundPool.count).to eq(1)

      inserted = BackgroundPool.refresh!(count: 3, candidates: candidates)
      expect(inserted).to eq(3)
      expect(BackgroundPool.count).to eq(3)

      stored_ids = BackgroundPool.ids
      expect(stored_ids).to match_array([900, 901, 902])
      expect(stored_ids).not_to include(777)  # old entry wiped
    end

    it 'caps inserts to count when fewer than candidates are wanted' do
      BackgroundPool.refresh!(count: 2, candidates: candidates)
      expect(BackgroundPool.count).to eq(2)
    end

    it 'persists author + unsplash_url alongside the picsum id' do
      BackgroundPool.refresh!(count: 1, candidates: [candidates[0]])
      row = BackgroundPool.entries.first
      expect(row['picsum_id']).to eq(900)
      expect(row['author']).to eq('A')
      expect(row['unsplash_url']).to eq('https://unsplash.com/p/a')
    end

    it 'raises RefreshError when Picsum returns nothing' do
      expect {
        BackgroundPool.refresh!(count: 5, candidates: [])
      }.to raise_error(BackgroundPool::RefreshError, /no candidates/)
    end

    it 'leaves the existing pool intact when fetch_candidates raises' do
      Database.connection.execute("INSERT INTO background_pool (picsum_id, author, unsplash_url) VALUES (?, ?, ?)",
                                  [333, 'Existing', 'https://example.com/x'])
      allow(BackgroundPool).to receive(:fetch_candidates).and_raise(BackgroundPool::RefreshError, 'HTTP 503')

      expect {
        BackgroundPool.refresh!
      }.to raise_error(BackgroundPool::RefreshError)

      # Pool still has the old row.
      expect(BackgroundPool.count).to eq(1)
      expect(BackgroundPool.ids).to eq([333])
    end
  end

  describe '.fetch_candidates' do
    it 'parses the Picsum /v2/list response into {id, author, url} hashes' do
      response = instance_double(Net::HTTPSuccess, code: '200', body: <<~JSON)
        [
          {"id":"5","author":"Alice","url":"https://unsplash.com/p/5","width":5000,"height":3000},
          {"id":"6","author":"Bob","url":"https://unsplash.com/p/6","width":5000,"height":3000}
        ]
      JSON
      allow(Providers::HttpClient).to receive(:get).and_return(response)

      out = BackgroundPool.fetch_candidates
      expect(out).to eq([
        { id: '5', author: 'Alice', url: 'https://unsplash.com/p/5' },
        { id: '6', author: 'Bob',   url: 'https://unsplash.com/p/6' }
      ])
    end

    it 'raises RefreshError on non-2xx HTTP' do
      response = instance_double(Net::HTTPNotFound, code: '404', body: 'nope')
      allow(Providers::HttpClient).to receive(:get).and_return(response)
      expect {
        BackgroundPool.fetch_candidates
      }.to raise_error(BackgroundPool::RefreshError, /HTTP 404/)
    end

    it 'raises RefreshError on malformed JSON' do
      response = instance_double(Net::HTTPSuccess, code: '200', body: 'not-json')
      allow(Providers::HttpClient).to receive(:get).and_return(response)
      expect {
        BackgroundPool.fetch_candidates
      }.to raise_error(BackgroundPool::RefreshError, /not valid JSON/)
    end
  end
end

RSpec.describe '/admin/backgrounds routes' do
  include Rack::Test::Methods

  def app
    require_relative '../app/main'
    TechFeedReader
  end

  describe 'GET /admin/backgrounds' do
    it 'renders the empty-state notice + the curated default IDs' do
      get '/admin/backgrounds'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('No custom pool yet')
      expect(last_response.body).to include('Refresh pool')
      BackgroundPool::DEFAULT_IDS.first(3).each do |id|
        expect(last_response.body).to include(id.to_s)
      end
    end

    it 'renders the populated pool with thumbnails + author' do
      Database.connection.execute("INSERT INTO background_pool (picsum_id, author, unsplash_url) VALUES (?, ?, ?)",
                                  [42, 'Sample Photographer', 'https://unsplash.com/p/42'])
      get '/admin/backgrounds'
      expect(last_response.body).to include('Sample Photographer')
      expect(last_response.body).to include('https://picsum.photos/id/42/320/180')
      expect(last_response.body).to include('https://unsplash.com/p/42')
      expect(last_response.body).not_to include('No custom pool yet')
    end
  end

  describe 'POST /admin/backgrounds/refresh' do
    let(:fake_candidates) do
      [
        { id: '11', author: 'Refreshed A', url: 'https://unsplash.com/p/11' },
        { id: '22', author: 'Refreshed B', url: 'https://unsplash.com/p/22' }
      ]
    end

    it 'calls BackgroundPool.refresh! and redirects with the inserted count' do
      allow(BackgroundPool).to receive(:fetch_candidates).and_return(fake_candidates)
      post '/admin/backgrounds/refresh'
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to include('/admin/backgrounds')
      expect(last_response.headers['Location']).to include('notice=refreshed')
    end

    it 'redirects with an error banner when refresh fails' do
      allow(BackgroundPool).to receive(:fetch_candidates).and_raise(BackgroundPool::RefreshError, 'HTTP 503')
      post '/admin/backgrounds/refresh'
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to include('error=refresh-failed')
    end
  end
end
