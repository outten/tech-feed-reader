require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/feed_recommender/claude'

# STUFF.md #23 — route specs for /feeds/ai-recommend. Stubs the
# FeedRecommender::Claude module so the suite stays hermetic (no API
# key, no live HTTP). Exercises happy path + every error branch the
# view renders.

RSpec.describe 'POST /feeds/ai-recommend' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  def stub_available(value)
    allow(FeedRecommender::Claude).to receive(:available?).and_return(value)
  end

  def stub_result(status:, recommendations: [], error: nil,
                  latency_ms: 42, model: 'claude-sonnet-4-6',
                  suggested: 0, validated: 0,
                  input_tokens: nil, output_tokens: nil)
    result = FeedRecommender::Claude::Result.new(
      status: status,
      recommendations: recommendations,
      raw: nil, model: model, latency_ms: latency_ms,
      input_tokens: input_tokens, output_tokens: output_tokens,
      error: error, prompt: 'food + travel',
      suggested_count: suggested, validated_count: validated
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
    stub_result(
      status: :ok,
      suggested: 1, validated: 1,
      recommendations: [
        { url: 'https://eater.com/rss/index.xml', title: 'Eater',
          kind: 'rss', rationale: 'Food culture coverage',
          entry_count: 20 }
      ]
    )
    post '/feeds/ai-recommend', { 'prompt' => 'food and travel writing' }
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Eater')
    expect(last_response.body).to include('Food culture coverage')
    # Subscribe form POSTs to /api/feeds (the manual-add JSON endpoint),
    # NOT /api/feeds/catalog/add (which rejects non-catalog URLs). The
    # js-ai-subscribe class lets our own handler in public/feeds-ai.js
    # claim the submit before public/feeds.js's catalog handler can.
    expect(last_response.body).to include('action="/api/feeds"')
    expect(last_response.body).to include('class="js-ai-subscribe"')
    expect(last_response.body).to include('value="https://eater.com/rss/index.xml"')
  end

  it 'preserves the user\'s prompt in the textarea so they can iterate' do
    stub_available(true)
    stub_result(status: :no_validated, suggested: 3, validated: 0)
    post '/feeds/ai-recommend', { 'prompt' => 'food + travel content' }
    expect(last_response.body).to include('food + travel content')
  end

  it 'shows the "no verified feeds" copy when Claude suggested URLs but none validated' do
    stub_available(true)
    stub_result(status: :no_validated, suggested: 5, validated: 0)
    post '/feeds/ai-recommend', { 'prompt' => 'super niche' }
    expect(last_response.body).to include('No verified feeds found')
    expect(last_response.body).to include('5 URLs')
  end

  it 'shows the "no verified feeds" copy when Claude returned zero suggestions' do
    stub_available(true)
    stub_result(status: :ok, suggested: 0, validated: 0, recommendations: [])
    post '/feeds/ai-recommend', { 'prompt' => 'unknown topic' }
    expect(last_response.body).to include('No verified feeds found')
    expect(last_response.body).to include("didn't have any known free feeds")
  end

  it 'surfaces a parse error with the underlying message' do
    stub_available(true)
    stub_result(status: :parse_error, error: 'JSON parse failed: unexpected token')
    post '/feeds/ai-recommend', { 'prompt' => 'x' }
    expect(last_response.body).to include("Response couldn't be parsed")
    expect(last_response.body).to include('unexpected token')
  end

  it 'surfaces an API error with its message' do
    stub_available(true)
    stub_result(status: :error, error: 'Anthropic::Errors::AuthenticationError: bad key')
    post '/feeds/ai-recommend', { 'prompt' => 'x' }
    expect(last_response.body).to include('AI call failed')
    expect(last_response.body).to include('bad key')
  end

  it 'mentions the validation gap when some suggestions failed' do
    stub_available(true)
    stub_result(
      status: :ok,
      suggested: 5, validated: 2,
      recommendations: [
        { url: 'https://a.example/rss', title: 'A', kind: 'rss', rationale: 'r' },
        { url: 'https://b.example/rss', title: 'B', kind: 'rss', rationale: 'r' }
      ]
    )
    post '/feeds/ai-recommend', { 'prompt' => 'p' }
    expect(last_response.body).to include('Claude suggested 5')
    expect(last_response.body).to include('2 validated as live feeds')
    expect(last_response.body).to include("3 couldn't be reached")
  end

  it 'renders the token-usage + estimated-cost line under recommendations' do
    stub_available(true)
    stub_result(
      status: :ok,
      suggested: 1, validated: 1,
      latency_ms: 1234,
      input_tokens: 4_000, output_tokens: 600,
      recommendations: [
        { url: 'https://x.example/rss', title: 'X', kind: 'rss', rationale: 'r' }
      ]
    )
    post '/feeds/ai-recommend', { 'prompt' => 'p' }
    expect(last_response.body).to include('4000 in / 600 out tokens')
    expect(last_response.body).to include('0.0210')
    expect(last_response.body).to include('1234ms')
  end

  it 'shows the thinking-indicator markup so JS can flip it on at submit' do
    stub_available(true)
    get '/feeds'
    expect(last_response.body).to include('class="ai-thinking"')
    expect(last_response.body).to include('AI is thinking…')
  end
end
