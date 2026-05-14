require_relative 'spec_helper'
require_relative '../app/feeds_store'
require_relative '../app/feed_recommender/claude'
require_relative '../app/feed_recommender/validator'

# STUFF.md #23. Specs cover the pure-Ruby surface of FeedRecommender
# (prompt builder, response parser) and the .recommend short-circuit
# branches. The live Anthropic API call + the Validator HTTP fetch are
# never exercised here.

RSpec.describe FeedRecommender::Claude do
  describe '.available?' do
    it 'is true iff ANTHROPIC_API_KEY is set' do
      original = ENV['ANTHROPIC_API_KEY']
      ENV['ANTHROPIC_API_KEY'] = nil
      expect(described_class.available?).to be(false)
      ENV['ANTHROPIC_API_KEY'] = 'sk-test'
      expect(described_class.available?).to be(true)
    ensure
      ENV['ANTHROPIC_API_KEY'] = original
    end
  end

  describe '.subscribed_lists' do
    it 'returns titles + a Set of urls' do
      FeedsStore.add(url: 'https://a.example/rss', title: 'Alpha')
      FeedsStore.add(url: 'https://b.example/rss', title: 'Bravo')
      titles, urls = described_class.subscribed_lists(1)
      expect(titles).to contain_exactly('Alpha', 'Bravo')
      expect(urls).to be_a(Set)
      expect(urls).to include('https://a.example/rss', 'https://b.example/rss')
    end

    it 'falls back to url when title is blank' do
      FeedsStore.add(url: 'https://no-title.example/rss')
      titles, _urls = described_class.subscribed_lists(1)
      expect(titles).to include('https://no-title.example/rss')
    end
  end

  describe '.build_user_message' do
    it 'includes prompt, subscribed-title block, and excluded-URL list' do
      msg = described_class.build_user_message(
        'food + travel content',
        ['Hacker News', 'Lobsters'],
        Set.new(['https://news.ycombinator.com/rss'])
      )
      expect(msg).to include("## User's request")
      expect(msg).to include('food + travel content')
      expect(msg).to include('Currently subscribed')
      expect(msg).to include('Hacker News')
      expect(msg).to include('Already-subscribed URLs')
      expect(msg).to include('https://news.ycombinator.com/rss')
    end

    it 'emits a friendly placeholder when there are no subscriptions yet' do
      msg = described_class.build_user_message('x', [], Set.new)
      expect(msg).to include('starting fresh')
    end
  end

  describe '.parse_response' do
    it 'parses a plain JSON object + normalises kind + dedupes' do
      raw = JSON.generate(recommendations: [
        { url: 'https://eater.com/rss/index.xml', title: 'Eater', kind: 'RSS', rationale: 'Food news' },
        { url: 'https://eater.com/rss/index.xml', title: 'Eater dup', kind: 'rss', rationale: 'duplicate' }
      ])
      parsed = described_class.parse_response(raw, Set.new)
      expect(parsed[:fallback]).to be(false)
      expect(parsed[:recommendations].length).to eq(1)
      pick = parsed[:recommendations].first
      expect(pick[:url]).to eq('https://eater.com/rss/index.xml')
      expect(pick[:kind]).to eq('rss')
      expect(pick[:rationale]).to eq('Food news')
    end

    it 'strips a ```json fence the model may sneak in' do
      raw = "```json\n#{JSON.generate(recommendations: [{ url: 'https://x.example/rss', title: 'X', kind: 'rss', rationale: 'r' }])}\n```"
      parsed = described_class.parse_response(raw, Set.new)
      expect(parsed[:recommendations].length).to eq(1)
    end

    it 'drops any url the user is already subscribed to' do
      subs = Set.new(['https://dup.example/rss'])
      raw = JSON.generate(recommendations: [
        { url: 'https://dup.example/rss',   title: 'Dup', kind: 'rss', rationale: 'r' },
        { url: 'https://fresh.example/rss', title: 'New', kind: 'rss', rationale: 'r' }
      ])
      parsed = described_class.parse_response(raw, subs)
      expect(parsed[:recommendations].map { |r| r[:url] }).to eq(['https://fresh.example/rss'])
    end

    it 'returns a fallback shape (no exception) on malformed JSON' do
      parsed = described_class.parse_response('not actually json', Set.new)
      expect(parsed[:fallback]).to be(true)
      expect(parsed[:recommendations]).to be_empty
      expect(parsed[:error]).to match(/parse failed/i)
    end

    it 'caps the recommendation count at MAX_RECOMMENDATIONS' do
      many = (1..20).map { |i| { url: "https://x#{i}.example/rss", title: "X#{i}", kind: 'rss', rationale: 'r' } }
      raw  = JSON.generate(recommendations: many)
      parsed = described_class.parse_response(raw, Set.new)
      expect(parsed[:recommendations].length).to eq(FeedRecommender::Claude::MAX_RECOMMENDATIONS)
    end

    it 'normalises an unknown kind value to "rss"' do
      raw = JSON.generate(recommendations: [{ url: 'https://x.example/rss', title: 'X', kind: 'unknown-kind', rationale: 'r' }])
      parsed = described_class.parse_response(raw, Set.new)
      expect(parsed[:recommendations].first[:kind]).to eq('rss')
    end
  end

  describe '.recommend (short-circuits without an API call)' do
    it 'returns :empty when prompt is blank' do
      result = described_class.recommend(1, prompt: '   ')
      expect(result.status).to eq(:empty)
    end

    it 'returns :unavailable when ANTHROPIC_API_KEY is not set' do
      original = ENV['ANTHROPIC_API_KEY']
      ENV['ANTHROPIC_API_KEY'] = nil
      result = described_class.recommend(1, prompt: 'food + travel')
      expect(result.status).to eq(:unavailable)
    ensure
      ENV['ANTHROPIC_API_KEY'] = original
    end
  end
end

RSpec.describe FeedRecommender::Validator do
  describe '.validate' do
    it 'returns :http_error on non-2xx responses' do
      fake_response = Struct.new(:code, :body).new('404', '')
      allow(Providers::HttpClient).to receive(:get).and_return(fake_response)
      result = described_class.validate('https://nope.example/rss')
      expect(result.status).to eq(:http_error)
      expect(result.error).to eq('HTTP 404')
    end

    it 'returns :not_a_feed when the body parses to no title + no entries' do
      fake_response = Struct.new(:code, :body).new('200', '<html>not a feed</html>')
      allow(Providers::HttpClient).to receive(:get).and_return(fake_response)
      result = described_class.validate('https://html.example/page')
      expect(result.status).to eq(:not_a_feed)
    end

    it 'returns :ok with the parsed title when the body looks like a feed' do
      atom = <<~XML
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Test Feed</title>
          <link href="https://feed.example/"/>
          <entry><title>An entry</title><id>1</id><link href="https://x"/><updated>2026-05-01T00:00:00Z</updated></entry>
        </feed>
      XML
      fake_response = Struct.new(:code, :body).new('200', atom)
      allow(Providers::HttpClient).to receive(:get).and_return(fake_response)
      result = described_class.validate('https://feed.example/atom.xml')
      expect(result.status).to eq(:ok)
      expect(result.title).to eq('Test Feed')
      expect(result.entry_count).to eq(1)
    end

    it 'returns :timeout when the HTTP layer raises a timeout' do
      allow(Providers::HttpClient).to receive(:get).and_raise(Net::OpenTimeout, 'execution expired')
      result = described_class.validate('https://slow.example/rss')
      expect(result.status).to eq(:timeout)
    end

    it 'returns :error on other connectivity failures' do
      allow(Providers::HttpClient).to receive(:get).and_raise(SocketError, 'no DNS')
      result = described_class.validate('https://bogus.example/rss')
      expect(result.status).to eq(:error)
    end
  end

  describe '.validate_many' do
    it 'preserves input order in the results' do
      r1 = FeedRecommender::Validator::Result.new(url: 'https://a/rss', status: :ok)
      r2 = FeedRecommender::Validator::Result.new(url: 'https://b/rss', status: :http_error)
      allow(described_class).to receive(:validate).with('https://a/rss', any_args).and_return(r1)
      allow(described_class).to receive(:validate).with('https://b/rss', any_args).and_return(r2)
      results = described_class.validate_many(['https://a/rss', 'https://b/rss'])
      expect(results.map(&:status)).to eq([:ok, :http_error])
    end
  end

  describe 'autodiscovery fallback' do
    let(:html_with_feed_link) do
      <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <link rel="alternate" type="application/rss+xml" title="Feed" href="https://example.com/real/feed.xml">
          </head>
          <body>Welcome</body>
        </html>
      HTML
    end

    let(:atom_body) do
      <<~XML
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Recovered Feed</title>
          <link href="https://example.com/"/>
          <entry><title>Hi</title><id>1</id><link href="https://x"/><updated>2026-05-01T00:00:00Z</updated></entry>
        </feed>
      XML
    end

    it 'recovers when the primary URL returns HTML with an autodiscoverable feed-link tag' do
      responses = {
        'https://example.com/wrong-path/'    => Struct.new(:code, :body).new('200', html_with_feed_link),
        'https://example.com/'               => Struct.new(:code, :body).new('200', html_with_feed_link),
        'https://example.com/real/feed.xml'  => Struct.new(:code, :body).new('200', atom_body)
      }
      allow(Providers::HttpClient).to receive(:get) { |url, **_| responses[url] || raise("unexpected URL: #{url}") }

      result = described_class.validate('https://example.com/wrong-path/')
      expect(result.status).to eq(:ok)
      expect(result.url).to eq('https://example.com/real/feed.xml')
      expect(result.title).to eq('Recovered Feed')
      expect(result.discovered_via).to eq('https://example.com/wrong-path/')
    end

    it 'recovers when the primary URL 404s but the domain root has a feed link' do
      responses = {
        'https://example.com/dead-path'      => Struct.new(:code, :body).new('404', ''),
        'https://example.com/'               => Struct.new(:code, :body).new('200', html_with_feed_link),
        'https://example.com/real/feed.xml'  => Struct.new(:code, :body).new('200', atom_body)
      }
      allow(Providers::HttpClient).to receive(:get) { |url, **_| responses[url] || raise("unexpected URL: #{url}") }

      result = described_class.validate('https://example.com/dead-path')
      expect(result.status).to eq(:ok)
      expect(result.url).to eq('https://example.com/real/feed.xml')
    end

    it 'returns the primary failure when autodiscovery finds nothing' do
      allow(Providers::HttpClient).to receive(:get).and_return(
        Struct.new(:code, :body).new('200', '<html><body>no feed here</body></html>')
      )
      result = described_class.validate('https://no-feed.example/page')
      expect(result.status).to eq(:not_a_feed)
      expect(result.discovered_via).to be_nil
    end
  end
end
