require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/triage/claude'
require_relative '../app/triage_store'

# Phase 8 cron — TriageStore persistence + /triage/:id historical view +
# Recent-runs list on the /triage manual page.

def triage_result(status: :ok, model: 'claude-sonnet-4-6', unread_count: 3,
                  must_read: nil, optional: nil, skip: nil, topic: nil)
  Triage::Claude::Result.new(
    status: status,
    must_read: must_read || [{ 'uid' => 'a', 'rationale' => 'r1' }],
    optional:  optional  || [{ 'uid' => 'b', 'rationale' => 'r2' }],
    skip:      skip      || [{ 'uid' => 'c', 'rationale' => 'r3' }],
    raw:           nil,
    model:         model,
    latency_ms:    123,
    input_tokens:  1500,
    output_tokens: 800,
    error:         nil,
    unread_count:  unread_count,
    topic:         topic
  )
end

RSpec.describe TriageStore do
  describe '.create' do
    it 'persists a triage row with all metadata + JSON-encoded groups' do
      id = TriageStore.create(1, triage_result)
      row = TriageStore.find(1, id)
      expect(row['status']).to eq('ok')
      expect(row['model']).to eq('claude-sonnet-4-6')
      expect(row['unread_count']).to eq(3)
      expect(row['latency_ms']).to eq(123)
      expect(row['input_tokens']).to eq(1500)
      expect(row['output_tokens']).to eq(800)
      expect(row['must_read']).to eq([{ 'uid' => 'a', 'rationale' => 'r1' }])
      expect(row['optional']).to eq([{ 'uid' => 'b', 'rationale' => 'r2' }])
      expect(row['skip']).to eq([{ 'uid' => 'c', 'rationale' => 'r3' }])
    end

    it 'persists a parse_error result so failures are auditable' do
      id = TriageStore.create(1, triage_result(status: :parse_error))
      row = TriageStore.find(1, id)
      expect(row['status']).to eq('parse_error')
    end

    it 'persists empty-state runs for the daily-history record' do
      id = TriageStore.create(1, triage_result(status: :empty, unread_count: 0,
                                            must_read: [], optional: [], skip: []))
      row = TriageStore.find(1, id)
      expect(row['unread_count']).to eq(0)
      expect(row['must_read']).to eq([])
    end
  end

  describe '.find' do
    it 'returns nil for an unknown id' do
      expect(TriageStore.find(1, 99_999)).to be_nil
    end

    it 'returns parsed group arrays (not the JSON strings)' do
      id = TriageStore.create(1, triage_result)
      row = TriageStore.find(1, id)
      expect(row['must_read']).to be_a(Array)
      expect(row['must_read'].first).to be_a(Hash)
    end
  end

  describe '.recent + .latest + .count' do
    it 'returns runs ordered newest-first' do
      first  = TriageStore.create(1, triage_result(unread_count: 1))
      sleep 0.01
      second = TriageStore.create(1, triage_result(unread_count: 2))

      ids = TriageStore.recent(1).map { |r| r['id'] }
      expect(ids.first).to eq(second)
      expect(ids.last).to eq(first)
      expect(TriageStore.latest(1)['id']).to eq(second)
      expect(TriageStore.count(1)).to eq(2)
    end

    it 'returns lightweight rows on .recent (no group JSON parse)' do
      TriageStore.create(1, triage_result)
      row = TriageStore.recent(1).first
      expect(row.keys).to include('id', 'generated_at', 'unread_count', 'status', 'model', 'topic')
      expect(row.keys).not_to include('must_read', 'optional', 'skip')
    end
  end

  # Phase S10 follow-up — daily cron writes one row per topic.
  describe '.create + .recent with topic (Phase S10 follow-up)' do
    it 'round-trips topic on create + find' do
      id = TriageStore.create(1, triage_result(topic: 'sports'))
      row = TriageStore.find(1, id)
      expect(row['topic']).to eq('sports')
    end

    it 'persists NULL topic for cross-topic legacy runs' do
      id = TriageStore.create(1, triage_result(topic: nil))
      row = TriageStore.find(1, id)
      expect(row['topic']).to be_nil
    end

    it '.recent(topic: ...) filters to that topic only' do
      TriageStore.create(1, triage_result(topic: nil))
      TriageStore.create(1, triage_result(topic: 'technology'))
      TriageStore.create(1, triage_result(topic: 'sports'))

      tech_rows   = TriageStore.recent(1, topic: 'technology')
      sports_rows = TriageStore.recent(1, topic: 'sports')
      cross_rows  = TriageStore.recent(1, topic: nil)

      expect(tech_rows.length).to eq(1)
      expect(tech_rows.first['topic']).to eq('technology')
      expect(sports_rows.length).to eq(1)
      expect(sports_rows.first['topic']).to eq('sports')
      expect(cross_rows.length).to eq(1)
      expect(cross_rows.first['topic']).to be_nil
    end

    it '.recent (no topic kwarg) returns rows across every topic' do
      TriageStore.create(1, triage_result(topic: nil))
      TriageStore.create(1, triage_result(topic: 'technology'))
      TriageStore.create(1, triage_result(topic: 'sports'))
      expect(TriageStore.recent(1).length).to eq(3)
    end
  end
end

RSpec.describe Triage::Claude, '#run topic plumbing (Phase S10 follow-up)' do
  before do
    ENV['ANTHROPIC_API_KEY'] = ''
  end
  after do
    ENV.delete('ANTHROPIC_API_KEY')
  end

  it 'sets Result.topic on :unavailable so the persisted row carries scope' do
    result = Triage::Claude.run(1, topic: 'sports')
    expect(result.status).to eq(:unavailable)
    expect(result.topic).to eq('sports')
  end

  it 'sets Result.topic on :empty so the persisted row carries scope' do
    ENV['ANTHROPIC_API_KEY'] = 'sk-test-fake-key'
    result = Triage::Claude.run(1, topic: 'technology')
    expect(result.status).to eq(:empty)
    expect(result.topic).to eq('technology')
  end
end

RSpec.describe '/triage routes (with persistence)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  describe 'GET /triage with persisted runs' do
    it 'lists recent runs in a Recent triage runs section' do
      TriageStore.create(1, triage_result(unread_count: 5))
      get '/triage'
      expect(last_response.body).to include('Recent triage runs')
      expect(last_response.body).to match(%r{<a href="/triage/\d+">View &rarr;</a>})
    end

    it 'omits the Recent runs section when no runs exist' do
      get '/triage'
      expect(last_response.body).not_to include('Recent triage runs')
    end
  end

  describe 'GET /triage/:id' do
    it 'renders a stored triage with all three groups' do
      feed = FeedsStore.add(url: 'https://x.com/triagecron', title: 'Cron')
      ArticlesStore.import(feed_id: feed['id'], entries: [
        { uid: 'cronuid00001', title: 'Article A', url: 'https://x.com/a', author: nil,
          published_at: '2026-05-08T12:00:00Z', content_html: '<p>x</p>', content_text: 'x',
          audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil }
      ])
      result = triage_result(must_read: [{ 'uid' => 'cronuid00001', 'rationale' => 'because reasons' }],
                              optional: [], skip: [])
      id = TriageStore.create(1, result)

      get "/triage/#{id}"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('Article A')
      expect(last_response.body).to include('because reasons')
      expect(last_response.body).to include('Must read')
    end

    it '404s on an unknown id' do
      get '/triage/99999'
      expect(last_response.status).to eq(404)
    end
  end

  describe 'POST /triage persistence' do
    around(:each) do |ex|
      ENV['ANTHROPIC_API_KEY'] = 'sk-test-fake-key'
      Triage::Claude.instance_variable_set(:@client, nil)
      ex.run
    ensure
      ENV.delete('ANTHROPIC_API_KEY')
      Triage::Claude.instance_variable_set(:@client, nil)
    end

    def stub_summary(text)
      block = double('TextBlock', type: :text, text: text)
      response = double('Message', content: [block], usage: nil)
      messages = double('Messages')
      allow(messages).to receive(:create).and_return(response)
      allow(Anthropic::Client).to receive(:new).and_return(double('Client', messages: messages))
    end

    it 'persists the result + flashes the new triage id in the page' do
      feed = FeedsStore.add(url: 'https://x.com/triagepersist', title: 'Persist')
      ArticlesStore.import(feed_id: feed['id'], entries: [
        { uid: 'persist00001', title: 'Persist me', url: 'https://x.com/p', author: nil,
          published_at: '2026-05-08T12:00:00Z', content_html: '<p>x</p>', content_text: 'x',
          audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil }
      ])
      stub_summary(JSON.generate(must_read: [{ uid: 'persist00001', rationale: 'fits the corpus' }],
                                  optional: [], skip: []))

      expect { post '/triage' }.to change { TriageStore.count(1) }.by(1)
      expect(last_response.body).to match(%r{Stored as triage <code>#\d+</code>})
    end

    it 'does NOT persist when status is :unavailable (no row worth keeping)' do
      ENV.delete('ANTHROPIC_API_KEY')
      expect { post '/triage' }.not_to change { TriageStore.count(1) }
    end
  end
end
