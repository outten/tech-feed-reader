require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/digests'
require_relative '../app/digest_store'
require_relative '../app/summarizer/claude'

# Manual Claude summary of a digest, cached on the digests row.
# Tests cover four layers:
#   1. Schema (migration applied — llm_* columns exist)
#   2. DigestStore.update_llm_summary
#   3. Summarizer::Claude.summarize_digest (SDK stubbed)
#   4. POST /digests/:id/summarize + GET /digests/:id view-surface

def make_digest(subject: 'Daily digest 2026-05-06',
                text_body: 'Article 1: foo. Article 2: bar.',
                html_body: '<p>foo bar</p>',
                window_hours: 24,
                article_count: 2)
  d = Struct.new(:generated_at, :window_hours, :count, :subject, :text, :html).new(
    Time.now.utc, window_hours, article_count, subject, text_body, html_body
  )
  id = DigestStore.create(1, d)
  DigestStore.find(1, id)
end

RSpec.describe DigestStore, '.update_llm_summary' do
  it 'persists summary + model + generated_at on the digest row' do
    digest = make_digest
    DigestStore.update_llm_summary(1, digest['id'], summary: 'A tight 4-sentence digest summary.', model: 'claude-opus-4-7')
    refreshed = DigestStore.find(1, digest['id'])
    expect(refreshed['llm_summary']).to eq('A tight 4-sentence digest summary.')
    expect(refreshed['llm_model']).to eq('claude-opus-4-7')
    expect(refreshed['llm_generated_at']).not_to be_nil
  end

  it 'returns 1 when the row was updated' do
    digest = make_digest
    expect(DigestStore.update_llm_summary(1, digest['id'], summary: 's', model: 'm')).to eq(1)
  end

  it 'returns 0 when the digest id does not exist' do
    expect(DigestStore.update_llm_summary(1, 99_999, summary: 's', model: 'm')).to eq(0)
  end

  it 'leaves other columns untouched' do
    digest = make_digest(subject: 'Original subject')
    DigestStore.update_llm_summary(1, digest['id'], summary: 's', model: 'm')
    refreshed = DigestStore.find(1, digest['id'])
    expect(refreshed['subject']).to eq('Original subject')
    expect(refreshed['text_body']).not_to be_empty
  end
end

RSpec.describe Summarizer::Claude, '.summarize_digest' do
  around(:each) do |ex|
    ENV['ANTHROPIC_API_KEY'] = 'sk-test-fake-key'
    Summarizer::Claude.instance_variable_set(:@client, nil)
    ex.run
  ensure
    ENV.delete('ANTHROPIC_API_KEY')
    Summarizer::Claude.instance_variable_set(:@client, nil)
  end

  def stub_response(text)
    block    = double('TextBlock', type: :text, text: text)
    response = double('Message', content: [block], usage: nil)
    messages = double('Messages')
    allow(messages).to receive(:create).and_return(response)
    allow(Anthropic::Client).to receive(:new).and_return(double('Client', messages: messages))
  end

  def capture_call_args
    captured = nil
    block    = double('TextBlock', type: :text, text: 'a digest summary')
    response = double('Message', content: [block], usage: nil)
    messages = double('Messages')
    allow(messages).to receive(:create) do |args|
      captured = args
      response
    end
    allow(Anthropic::Client).to receive(:new).and_return(double('Client', messages: messages))
    -> { captured }
  end

  it 'returns :unavailable when no API key is set' do
    ENV.delete('ANTHROPIC_API_KEY')
    result = Summarizer::Claude.summarize_digest(subject: 's', text_body: 'b')
    expect(result.status).to eq(:unavailable)
  end

  it 'returns :empty when the body is blank' do
    result = Summarizer::Claude.summarize_digest(subject: 's', text_body: '   ')
    expect(result.status).to eq(:empty)
  end

  it 'returns :ok with text + model on success' do
    stub_response('Four-sentence digest summary covering the main themes.')
    result = Summarizer::Claude.summarize_digest(subject: 'Today', text_body: 'Article 1: foo. Article 2: bar.')
    expect(result.status).to eq(:ok)
    expect(result.text).to include('Four-sentence')
    expect(result.model).to eq(Summarizer::Claude::MODEL)
  end

  it 'sends the digest-specific system prompt (not the article one)' do
    capture = capture_call_args
    Summarizer::Claude.summarize_digest(subject: 'Today', text_body: 'Article 1: foo.')
    args = capture.call
    expect(args[:system_]).to eq(Summarizer::Claude::DIGEST_SYSTEM_PROMPT)
    expect(args[:system_]).to include('news editor')
  end

  it 'truncates very long bodies at MAX_CONTENT chars' do
    captured = nil
    messages = double('Messages')
    allow(messages).to receive(:create) do |args|
      captured = args[:messages].first[:content]
      block    = double('TextBlock', type: :text, text: 'ok')
      double('Message', content: [block], usage: nil)
    end
    allow(Anthropic::Client).to receive(:new).and_return(double('Client', messages: messages))

    huge = 'x' * (Summarizer::Claude::MAX_CONTENT + 1000)
    Summarizer::Claude.summarize_digest(subject: 'big', text_body: huge)
    body_only = captured.sub(/\ASubject: big\n\n/, '')
    expect(body_only.length).to eq(Summarizer::Claude::MAX_CONTENT)
  end

  it 'returns :error on Anthropic SDK errors' do
    messages = double('Messages')
    allow(messages).to receive(:create).and_raise(StandardError.new('connection refused'))
    allow(Anthropic::Client).to receive(:new).and_return(double('Client', messages: messages))

    result = Summarizer::Claude.summarize_digest(subject: 's', text_body: 'b')
    expect(result.status).to eq(:error)
    expect(result.error).to include('connection refused')
  end
end

RSpec.describe '/digests/:id summarize routes' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  describe 'POST /digests/:id/summarize' do
    around(:each) do |ex|
      ENV['ANTHROPIC_API_KEY'] = 'sk-test-fake-key'
      Summarizer::Claude.instance_variable_set(:@client, nil)
      ex.run
    ensure
      ENV.delete('ANTHROPIC_API_KEY')
      Summarizer::Claude.instance_variable_set(:@client, nil)
    end

    def stub_summary(text)
      block = double('TextBlock', type: :text, text: text)
      response = double('Message', content: [block], usage: nil)
      messages = double('Messages')
      allow(messages).to receive(:create).and_return(response)
      allow(Anthropic::Client).to receive(:new).and_return(double('Client', messages: messages))
    end

    it 'persists the summary and redirects with notice on success' do
      stub_summary('A tight digest summary in 4 sentences.')
      digest = make_digest
      post "/digests/#{digest['id']}/summarize"
      expect(last_response.status).to eq(302)
      expect(last_response.location).to include('notice=llm-summarized')
      refreshed = DigestStore.find(1, digest['id'])
      expect(refreshed['llm_summary']).to include('tight digest')
      expect(refreshed['llm_model']).to eq(Summarizer::Claude::MODEL)
    end

    it 'reports cache hit (no API call) when summary already exists' do
      digest = make_digest
      DigestStore.update_llm_summary(1, digest['id'], summary: 'pre-cached', model: 'claude-opus-4-7')

      # Stub Anthropic to raise — if it gets called, the test fails.
      messages = double('Messages')
      allow(messages).to receive(:create).and_raise('SHOULD NOT BE CALLED')
      allow(Anthropic::Client).to receive(:new).and_return(double('Client', messages: messages))

      post "/digests/#{digest['id']}/summarize"
      expect(last_response.location).to include('notice=already-summarized')
      refreshed = DigestStore.find(1, digest['id'])
      expect(refreshed['llm_summary']).to eq('pre-cached')
    end

    it 'redirects with llm-unavailable when no API key' do
      ENV.delete('ANTHROPIC_API_KEY')
      digest = make_digest
      post "/digests/#{digest['id']}/summarize"
      expect(last_response.location).to include('error=llm-unavailable')
    end

    it 'redirects with llm-failed when Claude raises' do
      messages = double('Messages')
      allow(messages).to receive(:create).and_raise(StandardError.new('boom'))
      allow(Anthropic::Client).to receive(:new).and_return(double('Client', messages: messages))

      digest = make_digest
      post "/digests/#{digest['id']}/summarize"
      expect(last_response.location).to include('error=llm-failed')
    end

    it '404s on an unknown digest id' do
      post '/digests/99999/summarize'
      expect(last_response.status).to eq(404)
    end
  end

  describe 'GET /digests/:id view-surface' do
    it 'shows the Summarize button when no cached summary exists' do
      ENV['ANTHROPIC_API_KEY'] = 'sk-test-fake-key'
      digest = make_digest
      get "/digests/#{digest['id']}"
      expect(last_response.body).to include('Summarize with Claude')
      expect(last_response.body).to include("/digests/#{digest['id']}/summarize")
    ensure
      ENV.delete('ANTHROPIC_API_KEY')
    end

    # Loading state + Turbo opt-out for the 5-15s Claude call. Without
    # data-turbo="false", Turbo intercepts the POST and runs a silent
    # background fetch — the button looks dead. Without the JS the
    # click sits unchanged for the entire round-trip.
    it 'opts the Summarize form out of Turbo + loads the loading-state JS' do
      ENV['ANTHROPIC_API_KEY'] = 'sk-test-fake-key'
      digest = make_digest
      get "/digests/#{digest['id']}"
      expect(last_response.body).to match(%r{<form[^>]*action="/digests/#{digest['id']}/summarize"[^>]*data-turbo="false"})
      expect(last_response.body).to match(%r{<script src="/digest-summarize-form\.js})
    ensure
      ENV.delete('ANTHROPIC_API_KEY')
    end

    it 'hides the Summarize button + renders the cached summary when present' do
      digest = make_digest
      DigestStore.update_llm_summary(1, digest['id'], summary: 'My cached digest summary.', model: 'claude-opus-4-7')
      get "/digests/#{digest['id']}"
      expect(last_response.body).to include('My cached digest summary.')
      expect(last_response.body).to include('Claude summary')
      expect(last_response.body).not_to include('Summarize with Claude')
    end

    it 'omits the button when Claude is unavailable AND no cached summary exists' do
      ENV.delete('ANTHROPIC_API_KEY')
      digest = make_digest
      get "/digests/#{digest['id']}"
      expect(last_response.body).not_to include('Summarize with Claude')
    end
  end
end
