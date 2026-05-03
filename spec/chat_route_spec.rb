require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/chat'

RSpec.describe 'Chat routes' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  describe 'GET /chat/health' do
    it 'reports available=false when no key is set' do
      ENV.delete('ANTHROPIC_API_KEY')
      get '/chat/health'
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body['available']).to be(false)
      expect(body['model']).to eq(Chat::Claude::MODEL)
    end

    it 'reports available=true when a key is set' do
      ENV['ANTHROPIC_API_KEY'] = 'sk-test'
      get '/chat/health'
      body = JSON.parse(last_response.body)
      expect(body['available']).to be(true)
    ensure
      ENV.delete('ANTHROPIC_API_KEY')
    end
  end

  describe 'POST /chat' do
    around(:each) do |ex|
      ENV['ANTHROPIC_API_KEY'] = 'sk-test'
      Chat::Claude.instance_variable_set(:@client, nil)
      ex.run
    ensure
      ENV.delete('ANTHROPIC_API_KEY')
      Chat::Claude.instance_variable_set(:@client, nil)
    end

    def stub_chat(reply)
      block    = double('TextBlock', type: :text, text: reply)
      response = double('Message', content: [block])
      allow(response).to receive(:respond_to?).with(:usage).and_return(false)
      messages = double('Messages')
      allow(messages).to receive(:create).and_return(response)
      client = double('Client', messages: messages)
      allow(Anthropic::Client).to receive(:new).and_return(client)
      messages
    end

    it 'returns 200 + JSON reply on a successful turn' do
      stub_chat('Three sentences.')
      post '/chat',
           { message: 'sum it up', context: { url: '/article/x', title: 'X', excerpt: 'body' } }.to_json,
           'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body['status']).to eq('ok')
      expect(body['reply']).to eq('Three sentences.')
      expect(body['model']).to eq(Chat::Claude::MODEL)
    end

    it 'forwards request fields into Chat::Claude.respond' do
      captured = nil
      messages = stub_chat('ok')
      allow(messages).to receive(:create) do |args|
        captured = args
        block = double('TextBlock', type: :text, text: 'ok')
        resp  = double('Message', content: [block])
        allow(resp).to receive(:respond_to?).with(:usage).and_return(false)
        resp
      end

      post '/chat',
           {
             message: 'follow-up',
             history: [{ role: 'user', content: 'first' }, { role: 'assistant', content: 'reply' }],
             context: { url: '/podcasts', title: 'Podcasts', excerpt: 'episode list...' }
           }.to_json,
           'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to eq(200)
      # Last user message ships as the new turn; prior history precedes it.
      expect(captured[:messages].last).to eq(role: 'user', content: 'follow-up')
      expect(captured[:messages].length).to eq(3)
      # System prompt carries the page context.
      expect(captured[:system_]).to include('/podcasts')
      expect(captured[:system_]).to include('episode list')
    end

    it 'returns 400 on invalid JSON' do
      post '/chat', 'not-json', 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(400)
    end

    it 'returns 400 on empty message' do
      post '/chat', { message: '   ' }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(400)
      expect(JSON.parse(last_response.body)['status']).to eq('empty')
    end

    it 'returns 503 when Claude is not configured' do
      ENV.delete('ANTHROPIC_API_KEY')
      post '/chat', { message: 'hi' }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(503)
      expect(JSON.parse(last_response.body)['status']).to eq('unavailable')
    end

    it 'returns 500 when the API errors' do
      messages = double('Messages')
      err = Class.new(Anthropic::Errors::APIError) do
        def initialize(message); @message = message; end
        def message; @message; end
      end
      allow(messages).to receive(:create).and_raise(err.new('overloaded'))
      client = double('Client', messages: messages)
      allow(Anthropic::Client).to receive(:new).and_return(client)

      post '/chat', { message: 'hi' }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(500)
      expect(JSON.parse(last_response.body)['error']).to include('overloaded')
    end
  end

  describe 'chat widget surface' do
    it 'renders the widget container + bootstrap script on every page' do
      get '/health'  # any page that goes through layout — actually /health bypasses layout
      # use /admin instead — confirm layout-rendered page carries the widget
      allow_any_instance_of(TechFeedReader).to receive(:sidekiq_stats).and_return(
        ok: true, enqueued: 0, scheduled: 0, retries: 0, dead: 0,
        processed: 0, failed: 0, workers: 0
      )
      get '/admin'
      expect(last_response.body).to include('id="chat-widget"')
      expect(last_response.body).to include('chat-widget.js')
      expect(last_response.body).to include('window.PAGE_CONTEXT')
    end
  end
end
