require_relative 'spec_helper'
require_relative '../app/stock_follows_store'
require_relative '../app/stock_quotes_store'
require_relative '../app/stock_quote_provider'
require_relative '../app/stock_news_feed'
require_relative '../app/feeds_store'
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

  # --- StockNewsFeed ------------------------------------------------------

  describe StockNewsFeed do
    it 'url_for upcases the symbol and points at Yahoo headline RSS' do
      url = StockNewsFeed.url_for('cmcsa')
      expect(url).to start_with('https://feeds.finance.yahoo.com/rss/2.0/headline?s=CMCSA')
    end

    it 'stock_feed? recognises its own URLs and not others' do
      expect(StockNewsFeed.stock_feed?(StockNewsFeed.url_for('AAPL'))).to be true
      expect(StockNewsFeed.stock_feed?('https://news.ycombinator.com/rss')).to be false
    end

    it 'ensure_feed! creates a finance feed and is idempotent' do
      feed = StockNewsFeed.ensure_feed!('CMCSA', 'Comcast')
      expect(feed['topic']).to eq('finance')
      expect(feed['title']).to include('Comcast (CMCSA)')
      again = StockNewsFeed.ensure_feed!('CMCSA', 'Comcast')
      expect(again['id']).to eq(feed['id'])
    end

    it 'ensure_feed! falls back to the bare symbol when name is blank' do
      feed = StockNewsFeed.ensure_feed!('TSLA', nil)
      expect(feed['title']).to eq('TSLA — News')
    end
  end

  # --- Stock routes (via Rack::Test) --------------------------------------

  describe 'Stock routes' do
    include Rack::Test::Methods

    def app
      TechFeedReader
    end

    # The detail + follow routes enqueue a background FeedRefreshWorker
    # to populate symbol news; stub it so route specs stay off Redis.
    before do
      allow(FeedRefreshWorker).to receive(:perform_async)
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

    it 'GET /stocks/:symbol renders the Recent news section' do
      StockQuotesStore.upsert(symbol: 'CMCSA', name: 'Comcast', price: 40.0)
      allow(StockQuotesStore).to receive(:stale?).and_return(false)
      get '/stocks/CMCSA'
      expect(last_response).to be_ok
      expect(last_response.body).to include('Recent news')
    end

    it 'POST /stocks/follow subscribes the user to the symbol news feed' do
      post '/stocks/follow', symbol: 'CMCSA', name: 'Comcast'
      feed = FeedsStore.find_by_url(StockNewsFeed.url_for('CMCSA'))
      expect(feed).not_to be_nil
      expect(FeedsStore.subscribed?(1, feed['id'])).to be true
    end

    it 'POST /stocks/unfollow unsubscribes from the symbol news feed' do
      post '/stocks/follow', symbol: 'CMCSA', name: 'Comcast'
      feed = FeedsStore.find_by_url(StockNewsFeed.url_for('CMCSA'))
      post '/stocks/unfollow', symbol: 'CMCSA'
      expect(FeedsStore.subscribed?(1, feed['id'])).to be false
    end

    it 'GET /stocks/:symbol/news returns a pending section when the feed is cold' do
      get '/stocks/CMCSA/news'
      expect(last_response).to be_ok
      expect(last_response.body).to include('Recent news')
      expect(last_response.body).to include('data-stock-news-pending="CMCSA"')
    end

    it 'GET /stocks/:symbol/news renders items and drops the pending attr once articles exist' do
      allow(ArticlesStore).to receive(:recent_for_feed).and_return([
        { 'uid' => 'abc123', 'title' => 'CMCSA jumps 5%', 'published_at' => '2026-06-12T10:00:00Z', 'read' => 0, 'content_text' => '' }
      ])
      get '/stocks/CMCSA/news'
      expect(last_response).to be_ok
      expect(last_response.body).to include('CMCSA jumps 5%')
      expect(last_response.body).not_to include('data-stock-news-pending')
    end

    it 'GET /feeds hides stock-symbol feeds from the subscriptions list' do
      # A symbol feed the user is subscribed to should not appear...
      post '/stocks/follow', symbol: 'CMCSA', name: 'Comcast'
      # ...while a normal subscribed feed should.
      FeedsStore.add_for_user(user_id: 1, url: 'https://example.com/tech.xml', title: 'Tech Daily', topic: 'technology')
      get '/feeds'
      expect(last_response).to be_ok
      expect(last_response.body).to include('Tech Daily')
      expect(last_response.body).not_to include('Comcast (CMCSA)')
    end
  end

  # --- format_market_cap (via stock detail page) -------------------------

  describe 'market cap currency display' do
    include Rack::Test::Methods

    def app
      TechFeedReader
    end

    it 'shows $ prefix for USD market cap' do
      StockQuotesStore.upsert(symbol: 'AAPL', name: 'Apple', price: 100.0, market_cap: 1_230_000_000_000, currency: 'USD')
      get '/stocks/AAPL'
      expect(last_response).to be_ok
      expect(last_response.body).to include('$1.23T')
    end

    it 'shows — for non-USD market cap (no exchange rate available)' do
      StockQuotesStore.upsert(symbol: 'TSM', name: 'TSMC', price: 100.0, market_cap: 60_000_000_000_000, currency: 'TWD')
      get '/stocks/TSM'
      expect(last_response).to be_ok
      expect(last_response.body).not_to include('60.00T')
    end

    it 'shows $ for null currency (legacy row treated as USD)' do
      StockQuotesStore.upsert(symbol: 'XYZ', name: 'XYZ Corp', price: 100.0, market_cap: 500_000_000_000)
      get '/stocks/XYZ'
      expect(last_response).to be_ok
      expect(last_response.body).to include('$500.00B')
    end
  end

  # --- Global stock ticker (layout) --------------------------------------

  describe 'Global stock quotes table' do
    include Rack::Test::Methods

    def app
      TechFeedReader
    end

    it 'renders on a signed-in page when the user has quotes to show' do
      StockFollowsStore.add(user_id: 1, symbol: 'AAPL', name: 'Apple')
      StockQuotesStore.upsert(symbol: 'AAPL', name: 'Apple Inc', price: 200.0, change: 1.0, change_pct: 0.5)
      get '/articles'
      expect(last_response).to be_ok
      expect(last_response.body).to include('stock-grid')
      expect(last_response.body).to include('AAPL')
    end

    it 'shows followed symbols even when their cached quote is absent' do
      StockFollowsStore.add(user_id: 1, symbol: 'NVDA', name: 'NVIDIA')
      get '/articles'
      expect(last_response).to be_ok
      expect(last_response.body).to include('stock-grid')
      expect(last_response.body).to include('NVDA')
    end

    it 'always shows major index symbols even when their cached quote is absent' do
      get '/articles'
      expect(last_response).to be_ok
      expect(last_response.body).to include('stock-grid')
      StockQuoteProvider::MAJOR_INDICES.each do |idx|
        expect(last_response.body).to include(idx[:symbol])
      end
    end

    it 'shows ALL followed symbols in the rendered HTML, even with no cached quotes' do
      symbols = %w[AAPL TSM NVDA GOOG MSFT]
      symbols.each { |s| StockFollowsStore.add(user_id: 1, symbol: s, name: s) }
      get '/articles'
      expect(last_response).to be_ok
      symbols.each do |s|
        expect(last_response.body).to include(s), "expected stock grid to include #{s}"
      end
    end

  end

  # --- GET /api/ticker -------------------------------------------------------

  describe 'GET /api/ticker' do
    include Rack::Test::Methods

    def app
      TechFeedReader
    end

    it 'returns JSON array with all major indices even with cold cache' do
      get '/api/ticker'
      expect(last_response).to be_ok
      expect(last_response.content_type).to include('application/json')
      data = JSON.parse(last_response.body)
      expect(data).to be_an(Array)
      index_syms = StockQuoteProvider::MAJOR_INDICES.map { |i| i[:symbol] }
      returned_syms = data.map { |q| q['symbol'] }
      expect(index_syms - returned_syms).to be_empty
    end

    it 'includes followed symbol without cached quote' do
      StockFollowsStore.add(user_id: 1, symbol: 'TSLA', name: 'Tesla')
      get '/api/ticker'
      expect(last_response).to be_ok
      data = JSON.parse(last_response.body)
      tsla = data.find { |q| q['symbol'] == 'TSLA' }
      expect(tsla).not_to be_nil
      expect(tsla['name']).to eq('Tesla')
    end
  end
end
