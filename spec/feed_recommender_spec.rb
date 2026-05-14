require_relative 'spec_helper'
require_relative '../app/feeds_store'
require_relative '../app/feed_recommender/claude'

# STUFF.md #23. Specs cover the pure-Ruby surface of FeedRecommender
# (prompt builder, candidate filter, response parser) and the route
# integration that wires it onto /feeds. The live Anthropic API call is
# never exercised — we stub FeedRecommender::Claude.recommend at the
# route layer so the suite stays hermetic.

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

  describe '.build_candidates' do
    it 'excludes URLs the user is already subscribed to' do
      subscribed = Set.new(['https://news.ycombinator.com/rss'])
      candidates = described_class.build_candidates(subscribed)
      urls = candidates.map { |c| c[:url] }
      expect(urls).not_to include('https://news.ycombinator.com/rss')
      expect(urls).to include('https://lobste.rs/rss')
    end

    it 'returns each candidate with url / title / category / topic / blurb keys' do
      candidate = described_class.build_candidates(Set.new).first
      expect(candidate.keys).to include(:url, :title, :category, :topic, :blurb)
    end
  end

  describe '.build_subscribed_summary' do
    it 'groups subscribed catalog entries by topic + caps each group at 12' do
      urls = FeedCatalog::CATALOG.first(20).map { |e| e[:url] }.to_set
      summary = described_class.build_subscribed_summary(urls)
      expect(summary[:count]).to eq(urls.length)
      summary[:by_topic].each_value { |titles| expect(titles.length).to be <= 12 }
    end

    it 'returns an empty shape when the user has no subscriptions' do
      expect(described_class.build_subscribed_summary(Set.new)).to eq(count: 0, by_topic: {})
    end
  end

  describe '.build_user_message' do
    it 'includes the prompt, subscribed summary, and candidate JSON sections' do
      candidates = [{ url: 'https://x.com/rss', title: 'X', category: 'aggregator', topic: 'technology', blurb: 'X feed' }]
      summary    = { count: 0, by_topic: {} }
      msg = described_class.build_user_message('food + travel content', candidates, summary)
      expect(msg).to include('## User\'s request')
      expect(msg).to include('food + travel content')
      expect(msg).to include('## Currently subscribed')
      expect(msg).to include('## Candidate feeds')
      expect(msg).to include('https://x.com/rss')
    end
  end

  describe '.parse_response' do
    let(:candidates) do
      [
        { url: 'https://news.ycombinator.com/rss', title: 'Hacker News', category: 'aggregator', topic: 'technology', blurb: 'HN' },
        { url: 'https://lobste.rs/rss',           title: 'Lobsters',    category: 'aggregator', topic: 'technology', blurb: 'Lobsters' }
      ]
    end

    it 'parses a plain JSON object + attaches the catalog metadata' do
      raw = JSON.generate(recommendations: [
        { url: 'https://news.ycombinator.com/rss', rationale: 'Matches your tech focus' }
      ])
      parsed = described_class.parse_response(raw, candidates)
      expect(parsed[:fallback]).to be(false)
      expect(parsed[:recommendations].length).to eq(1)
      pick = parsed[:recommendations].first
      expect(pick[:url]).to eq('https://news.ycombinator.com/rss')
      expect(pick[:title]).to eq('Hacker News')
      expect(pick[:rationale]).to eq('Matches your tech focus')
    end

    it 'strips a ```json … ``` markdown fence the model occasionally sneaks in' do
      raw = "```json\n#{JSON.generate(recommendations: [{ url: 'https://lobste.rs/rss', rationale: 'good' }])}\n```"
      parsed = described_class.parse_response(raw, candidates)
      expect(parsed[:recommendations].length).to eq(1)
    end

    it 'drops invented URLs that aren\'t in the candidate set' do
      raw = JSON.generate(recommendations: [
        { url: 'https://made-up.example.com/feed', rationale: 'made up' },
        { url: 'https://lobste.rs/rss',            rationale: 'real' }
      ])
      parsed = described_class.parse_response(raw, candidates)
      expect(parsed[:recommendations].map { |r| r[:url] }).to eq(['https://lobste.rs/rss'])
    end

    it 'de-dupes a URL the model returns twice' do
      raw = JSON.generate(recommendations: [
        { url: 'https://lobste.rs/rss', rationale: 'first' },
        { url: 'https://lobste.rs/rss', rationale: 'duplicate' }
      ])
      parsed = described_class.parse_response(raw, candidates)
      expect(parsed[:recommendations].map { |r| r[:url] }).to eq(['https://lobste.rs/rss'])
    end

    it 'returns a fallback shape (no exception) on malformed JSON' do
      parsed = described_class.parse_response('not actually json', candidates)
      expect(parsed[:fallback]).to be(true)
      expect(parsed[:recommendations]).to be_empty
      expect(parsed[:error]).to match(/parse failed/i)
    end

    it 'caps the recommendation count at MAX_RECOMMENDATIONS' do
      many = (1..20).map { |i| { url: "https://x#{i}.example/rss", rationale: 'x' } }
      raw = JSON.generate(recommendations: many)
      candidates = (1..20).map { |i| { url: "https://x#{i}.example/rss", title: "X#{i}", category: 'c', topic: 't', blurb: 'b' } }
      parsed = described_class.parse_response(raw, candidates)
      expect(parsed[:recommendations].length).to eq(FeedRecommender::Claude::MAX_RECOMMENDATIONS)
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

    it 'returns :no_candidates when the user is subscribed to every catalog entry' do
      original = ENV['ANTHROPIC_API_KEY']
      ENV['ANTHROPIC_API_KEY'] = 'sk-test'
      FeedCatalog::CATALOG.each { |entry| FeedsStore.add(url: entry[:url], title: entry[:title]) }
      result = described_class.recommend(1, prompt: 'food + travel')
      expect(result.status).to eq(:no_candidates)
    ensure
      ENV['ANTHROPIC_API_KEY'] = original
    end
  end
end
