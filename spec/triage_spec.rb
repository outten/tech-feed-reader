require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/read_state_store'
require_relative '../app/triage/claude'
require_relative '../app/triage_store'

# Phase 8 — AI-assisted triage. Specs cover three layers:
#   1. Triage::Claude.available?      (env-key gating)
#   2. Triage::Claude.run(1)             (SDK stubbed, parser, error paths)
#   3. /triage routes (GET + POST)    (view surface)
#
# Anthropic SDK is fully stubbed — no real network calls in test env.

def make_triage_article(uid:, title:, content_text: 'placeholder body', published_at: '2026-05-06T12:00:00Z')
  feed = FeedsStore.find_by_url('https://x.com/triage-rss') ||
         FeedsStore.add(url: 'https://x.com/triage-rss', title: 'Triage Feed')
  ArticlesStore.import(feed_id: feed['id'], entries: [{
    uid: uid, title: title, url: "https://x.com/#{uid}",
    author: nil, published_at: published_at,
    content_html: "<p>#{content_text}</p>", content_text: content_text,
    audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
  }])
  ArticlesStore.find_by_uid(uid)
end

RSpec.describe Triage::Claude, '.available?' do
  it 'is false when ANTHROPIC_API_KEY is unset' do
    ENV.delete('ANTHROPIC_API_KEY')
    expect(Triage::Claude.available?).to be(false)
  end

  it 'is true when ANTHROPIC_API_KEY is set' do
    ENV['ANTHROPIC_API_KEY'] = 'sk-test-fake-key'
    expect(Triage::Claude.available?).to be(true)
  ensure
    ENV.delete('ANTHROPIC_API_KEY')
  end
end

RSpec.describe Triage::Claude, '.run' do
  around(:each) do |ex|
    ENV['ANTHROPIC_API_KEY'] = 'sk-test-fake-key'
    Triage::Claude.instance_variable_set(:@client, nil)
    ex.run
  ensure
    ENV.delete('ANTHROPIC_API_KEY')
    Triage::Claude.instance_variable_set(:@client, nil)
  end

  def stub_response(text)
    block    = double('TextBlock', type: :text, text: text)
    response = double('Message', content: [block], usage: nil)
    messages = double('Messages')
    allow(messages).to receive(:create).and_return(response)
    client = double('Client', messages: messages)
    allow(Anthropic::Client).to receive(:new).and_return(client)
  end

  def capture_call_args
    captured = nil
    block    = double('TextBlock', type: :text, text: '{"must_read":[],"optional":[],"skip":[]}')
    response = double('Message', content: [block], usage: nil)
    messages = double('Messages')
    allow(messages).to receive(:create) do |args|
      captured = args
      response
    end
    client = double('Client', messages: messages)
    allow(Anthropic::Client).to receive(:new).and_return(client)
    -> { captured }
  end

  it 'returns :unavailable when no API key is set' do
    ENV.delete('ANTHROPIC_API_KEY')
    result = Triage::Claude.run(1)
    expect(result.status).to eq(:unavailable)
  end

  it 'returns :empty when there are no unread articles' do
    # No DB rows at all → empty state.
    result = Triage::Claude.run(1)
    expect(result.status).to eq(:empty)
    expect(result.must_read).to eq([])
  end

  it 'parses a happy-path JSON response into the three groups' do
    art = make_triage_article(uid: 'triage000001', title: 'Article one')
    art2 = make_triage_article(uid: 'triage000002', title: 'Article two')
    art3 = make_triage_article(uid: 'triage000003', title: 'Article three')

    stub_response(JSON.generate(
      must_read: [{ uid: art['uid'], rationale: 'matches your bookmarked Ruby work' }],
      optional:  [{ uid: art2['uid'], rationale: 'might interest you' }],
      skip:      [{ uid: art3['uid'], rationale: 'low relevance' }]
    ))

    result = Triage::Claude.run(1)
    expect(result.status).to eq(:ok)
    expect(result.must_read.length).to eq(1)
    expect(result.must_read.first['uid']).to eq('triage000001')
    expect(result.must_read.first['rationale']).to include('Ruby')
    expect(result.optional.length).to eq(1)
    expect(result.skip.length).to eq(1)
  end

  it 'strips markdown code fences before parsing' do
    art = make_triage_article(uid: 'triagefence01', title: 'Fenced')
    stub_response("```json\n#{JSON.generate(must_read: [{ uid: art['uid'], rationale: 'r' }], optional: [], skip: [])}\n```")
    result = Triage::Claude.run(1)
    expect(result.status).to eq(:ok)
    expect(result.must_read.first['uid']).to eq('triagefence01')
  end

  it 'salvages a JSON object embedded in surrounding prose' do
    art = make_triage_article(uid: 'triagesalvg1', title: 'Salvage me')
    stub_response("Here's my analysis: #{JSON.generate(must_read: [{ uid: art['uid'], rationale: 'r' }], optional: [], skip: [])} hope that helps!")
    result = Triage::Claude.run(1)
    expect(result.status).to eq(:ok)
    expect(result.must_read.first['uid']).to eq('triagesalvg1')
  end

  it 'falls back to skip-all on un-parseable output (status :parse_error)' do
    art = make_triage_article(uid: 'triagefail001', title: 'Unparsable')
    stub_response('this is not JSON and cannot be salvaged')
    result = Triage::Claude.run(1)
    expect(result.status).to eq(:parse_error)
    expect(result.must_read).to eq([])
    expect(result.skip.length).to eq(1)
    expect(result.skip.first['uid']).to eq('triagefail001')
    expect(result.error).to include('parse failure')
  end

  # Regression for production parse failures on 2026-05-10: Sonnet 4.6
  # second-guessed itself mid-response, emitting a first JSON block,
  # then "Wait, I made errors. Let me redo this cleanly with..." plus
  # a second corrected JSON block. The old salvage took raw[first..last]
  # which spans BOTH blocks + the prose between, so it never parsed.
  it 'recovers when Claude emits a second "let me redo" JSON block after a wrong first attempt' do
    art = make_triage_article(uid: 'triageredo001', title: 'Redo me')
    first_attempt  = JSON.generate(must_read: [{ uid: 'wrong-uid', rationale: 'first attempt' }],
                                   optional: [], skip: [])
    second_attempt = JSON.generate(must_read: [{ uid: art['uid'], rationale: 'corrected' }],
                                   optional: [], skip: [])
    stub_response("```json\n#{first_attempt}\n```\n\nWait, I made errors with duplicates. Let me redo this cleanly with the right uids:\n\n```json\n#{second_attempt}\n```")
    result = Triage::Claude.run(1)
    expect(result.status).to eq(:ok)
    expect(result.must_read.first['uid']).to eq('triageredo001')
    expect(result.must_read.first['rationale']).to eq('corrected')
  end

  it 'recovers when two JSON blocks are separated by prose without code fences' do
    art = make_triage_article(uid: 'triageredo002', title: 'No fences redo')
    first_attempt  = JSON.generate(must_read: [], optional: [], skip: [{ uid: 'unused', rationale: 'first' }])
    second_attempt = JSON.generate(must_read: [{ uid: art['uid'], rationale: 'final' }],
                                   optional: [], skip: [])
    stub_response("#{first_attempt}\n\nLet me redo this cleanly:\n\n#{second_attempt}")
    result = Triage::Claude.run(1)
    expect(result.status).to eq(:ok)
    expect(result.must_read.first['uid']).to eq('triageredo002')
  end

  it 'extract_json_candidates ignores braces inside JSON string literals' do
    raw = '{"must_read": [{"uid": "a", "rationale": "matches \"{example}\""}], "optional": [], "skip": []}'
    candidates = Triage::Claude.extract_json_candidates(raw)
    expect(candidates.length).to eq(1)
    expect(candidates.first).to eq(raw)
  end

  it 'persists the raw model output on every triage row' do
    art = make_triage_article(uid: 'triageraw0001', title: 'Saved raw')
    stub_response(JSON.generate(must_read: [{ uid: art['uid'], rationale: 'r' }], optional: [], skip: []))
    result = Triage::Claude.run(1)
    id = TriageStore.create(1, result)
    row = Database.connection.execute('SELECT raw FROM triages WHERE id = ?', [id]).first
    expect(row['raw']).to include(art['uid'])
  end

  it 'includes the positive corpus excerpts in the user prompt' do
    pos = make_triage_article(uid: 'triagepos0001', title: 'Liked Ruby piece', content_text: 'rails ruby routing')
    ReadStateStore.mark_bookmarked(1, pos['id'], value: true)
    ReadStateStore.mark_read(1, pos['id'], read: true)

    make_triage_article(uid: 'triageunread1', title: 'Unread one')

    capture = capture_call_args
    Triage::Claude.run(1)
    args = capture.call
    user_msg = args[:messages].first[:content]

    expect(user_msg).to include('Positive corpus')
    expect(user_msg).to include('Liked Ruby piece')
    expect(user_msg).to include('Unread articles to triage')
    expect(user_msg).to include('triageunread1')
  end

  it 'caps unread excerpts at EXCERPT_CHARS' do
    long = 'x' * (Triage::Claude::EXCERPT_CHARS + 200)
    make_triage_article(uid: 'triagebig0001', title: 'Big body', content_text: long)

    capture = capture_call_args
    Triage::Claude.run(1)
    args = capture.call
    user_msg = args[:messages].first[:content]

    # The line for triagebig0001 should be ≤ EXCERPT_CHARS + a small
    # header overhead. Verify the excerpt itself didn't smuggle the
    # full long string through.
    expect(user_msg).not_to include('x' * (Triage::Claude::EXCERPT_CHARS + 100))
  end

  it 'sends Sonnet, not Opus (per the cost guard)' do
    make_triage_article(uid: 'triagemodel01', title: 'Model check')
    capture = capture_call_args
    Triage::Claude.run(1)
    args = capture.call
    expect(args[:model]).to eq(Triage::Claude::MODEL.to_sym)
    expect(Triage::Claude::MODEL).to start_with('claude-sonnet-')
  end

  it 'returns :error on Anthropic SDK errors' do
    make_triage_article(uid: 'triageerr0001', title: 'Boom')
    messages = double('Messages')
    allow(messages).to receive(:create).and_raise(StandardError.new('connection refused'))
    client = double('Client', messages: messages)
    allow(Anthropic::Client).to receive(:new).and_return(client)

    result = Triage::Claude.run(1)
    expect(result.status).to eq(:error)
    expect(result.error).to include('connection refused')
  end

  it 'caps unread to UNREAD_LIMIT articles in the prompt' do
    (Triage::Claude::UNREAD_LIMIT + 5).times do |i|
      make_triage_article(uid: "triagecap#{i.to_s.rjust(4, '0')}", title: "Article #{i}")
    end

    capture = capture_call_args
    Triage::Claude.run(1)
    args = capture.call
    user_msg = args[:messages].first[:content]

    # uid lines = lines starting with "- uid="; we expect exactly UNREAD_LIMIT.
    uid_lines = user_msg.scan(/^- uid=/).length
    expect(uid_lines).to eq(Triage::Claude::UNREAD_LIMIT)
  end
end

RSpec.describe '/triage routes' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  describe 'GET /triage' do
    it 'renders the empty state with a Generate button when API key is unset' do
      ENV.delete('ANTHROPIC_API_KEY')
      get '/triage'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('Generate triage now')
      expect(last_response.body).to include("Claude isn't configured")
    end

    it 'renders the empty state with an enabled button when API key is set' do
      ENV['ANTHROPIC_API_KEY'] = 'sk-test-fake-key'
      get '/triage'
      expect(last_response.body).to include('Generate triage now')
      expect(last_response.body).not_to include('disabled')
    ensure
      ENV.delete('ANTHROPIC_API_KEY')
    end

    # Loading state: disable button + swap text on submit so the user
    # sees feedback during the 10-30s Claude call.
    it 'wires the triage-form.js loading-state script' do
      get '/triage'
      expect(last_response.body).to match(%r{<script src="/triage-form\.js})
    end

    # Turbo intercepts form submits and runs a background fetch. For a
    # 30s Claude call that means no visible progress — clicks look dead.
    # Forms posting to /triage opt out via data-turbo="false" so the
    # browser does classic full-page navigation.
    it 'opts the Generate form out of Turbo' do
      get '/triage'
      expect(last_response.body).to match(%r{<form[^>]*action="/triage"[^>]*data-turbo="false"})
    end
  end

  describe 'POST /triage' do
    around(:each) do |ex|
      ENV['ANTHROPIC_API_KEY'] = 'sk-test-fake-key'
      Triage::Claude.instance_variable_set(:@client, nil)
      ex.run
    ensure
      ENV.delete('ANTHROPIC_API_KEY')
      Triage::Claude.instance_variable_set(:@client, nil)
    end

    it 'renders the must_read / optional / skip groups with rationales' do
      art_a = make_triage_article(uid: 'triageroute01', title: 'Route A')
      art_b = make_triage_article(uid: 'triageroute02', title: 'Route B')

      block = double('TextBlock', type: :text, text: JSON.generate(
        must_read: [{ uid: art_a['uid'], rationale: 'high relevance signal' }],
        optional:  [],
        skip:      [{ uid: art_b['uid'], rationale: 'low relevance signal' }]
      ))
      response = double('Message', content: [block], usage: nil)
      messages = double('Messages')
      allow(messages).to receive(:create).and_return(response)
      allow(Anthropic::Client).to receive(:new).and_return(double('Client', messages: messages))

      post '/triage'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('Must read')
      expect(last_response.body).to include('Route A')
      expect(last_response.body).to include('high relevance signal')
      expect(last_response.body).to include('Route B')
      expect(last_response.body).to include('low relevance signal')
      expect(last_response.body).to include('Regenerate')
    end

    it 'renders the empty state when there are no unread articles' do
      block = double('TextBlock', type: :text, text: '{}')
      response = double('Message', content: [block], usage: nil)
      messages = double('Messages')
      allow(messages).to receive(:create).and_return(response)
      allow(Anthropic::Client).to receive(:new).and_return(double('Client', messages: messages))

      post '/triage'
      expect(last_response.body).to include('All caught up')
    end
  end
end
