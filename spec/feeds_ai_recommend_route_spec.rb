require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/feed_recommender/claude'

# STUFF.md #23 — route specs for /feeds/ai-recommend. Stubs the
# FeedRecommender::Claude module so the suite stays hermetic (no API key
# needed). Exercises happy path + every error branch the view renders.

RSpec.describe 'POST /feeds/ai-recommend' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  def stub_available(value)
    allow(FeedRecommender::Claude).to receive(:available?).and_return(value)
  end

  def stub_result(status:, recommendations: [], error: nil, latency_ms: 42, model: 'claude-sonnet-4-6')
    result = FeedRecommender::Claude::Result.new(
      status: status,
      recommendations: recommendations,
      raw: nil, model: model, latency_ms: latency_ms,
      input_tokens: nil, output_tokens: nil,
      error: error, prompt: 'food + travel'
    )
    allow(FeedRecommender::Claude).to receive(:recommend).and_return(result)
  end

  it 'renders the input box on GET /feeds when ANTHROPIC_API_KEY is set' do
    stub_available(true)
    get '/feeds'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Ask AI for feed ideas')
    expect(last_response.body).to include('name="prompt"')
  end

  it 'hides the input box on GET /feeds when no API key is set' do
    stub_available(false)
    get '/feeds'
    expect(last_response.body).not_to include('Ask AI for feed ideas')
  end

  it 'renders recommendations + their rationales on POST when status: :ok' do
    stub_available(true)
    stub_result(status: :ok, recommendations: [
      { url: 'https://lobste.rs/rss', title: 'Lobsters', category: 'aggregator',
        topic: 'technology', blurb: 'Programmer-curated link aggregator with a comments culture.',
        rationale: 'Matches your interest in software development' }
    ])
    post '/feeds/ai-recommend', { 'prompt' => 'I love programming + tech culture' }
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Lobsters')
    expect(last_response.body).to include('Matches your interest in software development')
    expect(last_response.body).to include('action="/feeds/catalog/add"')
  end

  it 'preserves the user\'s prompt in the textarea so they can iterate' do
    stub_available(true)
    stub_result(status: :ok, recommendations: [])
    post '/feeds/ai-recommend', { 'prompt' => 'food + travel content' }
    expect(last_response.body).to include('food + travel content')
  end

  it 'shows a friendly "no matches" message when Claude returns an empty array' do
    stub_available(true)
    stub_result(status: :ok, recommendations: [])
    post '/feeds/ai-recommend', { 'prompt' => 'something extremely niche' }
    expect(last_response.body).to include("didn't find anything matching")
  end

  it 'surfaces a parse error with the underlying message' do
    stub_available(true)
    stub_result(status: :parse_error, error: 'JSON parse failed: unexpected token')
    post '/feeds/ai-recommend', { 'prompt' => 'x' }
    expect(last_response.body).to include('AI response')
    expect(last_response.body).to include('unexpected token')
  end

  it 'surfaces an API error with its message' do
    stub_available(true)
    stub_result(status: :error, error: 'Anthropic::Errors::AuthenticationError: bad key')
    post '/feeds/ai-recommend', { 'prompt' => 'x' }
    expect(last_response.body).to include('AI call failed')
    expect(last_response.body).to include('bad key')
  end

  it 'shows the "fully subscribed" message when there are no candidates left' do
    stub_available(true)
    stub_result(status: :no_candidates)
    post '/feeds/ai-recommend', { 'prompt' => 'x' }
    expect(last_response.body).to include('already subscribed to every feed')
  end
end
