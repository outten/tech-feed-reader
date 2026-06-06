require_relative 'spec_helper'
require_relative '../app/stock_follows_store'
require_relative '../app/stock_quotes_store'
require_relative '../app/stock_quote_provider'
require_relative '../app/main'

RSpec.describe 'Stock follows & quotes' do
  # Test user seeded by spec_helper (id=1, 't-money')
  let(:uid) { 1 }

  # --- StockFollowsStore -------------------------------------------------

  describe StockFollowsStore do
    it 'add + follow? + all + count' do
      expect(StockFollowsStore.add(user_id: uid, symbol: 'AAPL', name: 'Apple')).to be true
      expect(StockFollowsStore.follow?(uid, 'AAPL')).to be true
      expect(StockFollowsStore.follow?(uid, 'MSFT')).to be false
      expect(StockFollowsStore.count(uid)).to eq(1)
      expect(StockFollowsStore.all(uid).first['symbol']).to eq('AAPL')
    end

    it 'add is idempotent' do
      StockFollowsStore.add(user_id: uid, symbol: 'AAPL')
      expect(StockFollowsStore.add(user_id: uid, symbol: 'AAPL')).to be false
      expect(StockFollowsStore.count(uid)).to eq(1)
    end

    it 'upcases symbol on add and follow?' do
      StockFollowsStore.add(user_id: uid, symbol: 'aapl')
      expect(StockFollowsStore.follow?(uid, 'aapl')).to be true
      expect(StockFollowsStore.follow?(uid, 'AAPL')).to be true
    end

    it 'remove returns affected count' do
      StockFollowsStore.add(user_id: uid, symbol: 'GOOG')
      expect(StockFollowsStore.remove(user_id: uid, symbol: 'GOOG')).to be >= 1
      expect(StockFollowsStore.follow?(uid, 'GOOG')).to be false
    end

    it 'distinct_symbols returns unique symbols across users' do
      StockFollowsStore.add(user_id: uid, symbol: 'TSLA')
      expect(StockFollowsStore.distinct_symbols).to include('TSLA')
    end

    it 'rejects empty symbol' do
      expect { StockFollowsStore.add(user_id: uid, symbol: '') }.to raise_error(ArgumentError)
    end
  end

  # --- StockQuotesStore ---------------------------------------------------

  describe StockQuotesStore do
    it 'upsert + find' do
      StockQuotesStore.upsert(symbol: 'TEST1', name: 'Test Corp', price: 123.45, change: 1.23, change_pct: 1.01)
      row = StockQuotesStore.find('TEST1')
      expect(row).not_to be_nil
      expect(row['name']).to eq('Test Corp')
      expect(row['price'].to_f).to be_within(0.01).of(123.45)
    end

    it 'upsert updates existing row (COALESCE preserves non-nil)' do
      StockQuotesStore.upsert(symbol: 'TEST1', name: 'Test Corp', exchange: 'NYSE')
      StockQuotesStore.upsert(symbol: 'TEST1', price: 200.00)
      row = StockQuotesStore.find('TEST1')
      expect(row['name']).to eq('Test Corp')   # preserved via COALESCE
      expect(row['price'].to_f).to be_within(0.01).of(200.00)
    end

    it 'find_many returns multiple quotes' do
      StockQuotesStore.upsert(symbol: 'TEST1', name: 'Test1')
      StockQuotesStore.upsert(symbol: 'TEST2', name: 'Test2')
      rows = StockQuotesStore.find_many(%w[TEST1 TEST2])
      expect(rows.length).to eq(2)
    end

    it 'find_many with empty array returns empty' do
      expect(StockQuotesStore.find_many([])).to eq([])
    end

    it 'stale? returns true for missing symbol' do
      expect(StockQuotesStore.stale?('NONEXISTENT')).to be true
    end

    it 'stale? returns false for freshly upserted symbol' do
      StockQuotesStore.upsert(symbol: 'TEST1', name: 'Fresh')
      expect(StockQuotesStore.stale?('TEST1', max_age_seconds: 60)).to be false
    end
  end

  # --- StockQuoteProvider -------------------------------------------------

  describe StockQuoteProvider do
    it 'MAJOR_INDICES has at least 5 entries' do
      expect(StockQuoteProvider::MAJOR_INDICES.length).to be >= 5
    end

    it 'available? returns false when key is unset' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('FINNHUB_API_KEY').and_return(nil)
      expect(StockQuoteProvider.available?).to be false
    end

    it 'search returns empty when API key is missing' do
      allow(StockQuoteProvider).to receive(:available?).and_return(false)
      expect(StockQuoteProvider.search('Apple')).to eq([])
    end

    it 'quote returns nil when API key is missing' do
      allow(StockQuoteProvider).to receive(:available?).and_return(false)
      expect(StockQuoteProvider.quote('AAPL')).to be_nil
    end
  end

  # --- Stock routes (via Rack::Test) --------------------------------------

  describe 'Stock routes' do
    include Rack::Test::Methods

    def app
      TechFeedReader
    end

    it 'GET /stocks renders the search page' do
      get '/stocks'
      expect(last_response).to be_ok
      expect(last_response.body).to include('Stocks')
      expect(last_response.body).to include('Search by company name')
    end

    it 'GET /stocks?q=Apple includes search results section' do
      allow(StockQuoteProvider).to receive(:search).with('Apple').and_return([
        { symbol: 'AAPL', description: 'Apple Inc', type: 'Common Stock' }
      ])
      get '/stocks', q: 'Apple'
      expect(last_response).to be_ok
      expect(last_response.body).to include('AAPL')
    end

    it 'GET /stocks/:symbol renders the detail page' do
      StockQuotesStore.upsert(symbol: 'AAPL', name: 'Apple Inc', price: 307.34, change: -3.89, change_pct: -1.25)
      allow(StockQuotesStore).to receive(:stale?).and_return(false)
      get '/stocks/AAPL'
      expect(last_response).to be_ok
      expect(last_response.body).to include('Apple Inc')
      expect(last_response.body).to include('307.34')
    end

    it 'POST /stocks/follow adds the follow and returns JSON' do
      header 'Accept', 'application/json'
      post '/stocks/follow', symbol: 'MSFT', name: 'Microsoft'
      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json['ok']).to be true
      expect(json['followed']).to be true
      expect(json['symbol']).to eq('MSFT')
    end

    it 'POST /stocks/unfollow removes the follow and returns JSON' do
      StockFollowsStore.add(user_id: 1, symbol: 'MSFT')
      header 'Accept', 'application/json'
      post '/stocks/unfollow', symbol: 'MSFT'
      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json['followed']).to be false
    end

    it 'POST /stocks/follow with empty symbol returns 400' do
      post '/stocks/follow', symbol: ''
      expect(last_response.status).to eq(400)
    end
  end
end
