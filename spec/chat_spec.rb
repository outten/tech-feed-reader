require_relative 'spec_helper'
require_relative '../app/chat'

RSpec.describe Chat::Claude do
  describe '.available?' do
    it 'is false when ANTHROPIC_API_KEY is unset' do
      ENV.delete('ANTHROPIC_API_KEY')
      expect(Chat::Claude.available?).to be(false)
    end

    it 'is true when ANTHROPIC_API_KEY is set' do
      ENV['ANTHROPIC_API_KEY'] = 'sk-test-fake-key'
      expect(Chat::Claude.available?).to be(true)
    ensure
      ENV.delete('ANTHROPIC_API_KEY')
    end
  end

  describe '.respond' do
    around(:each) do |ex|
      ENV['ANTHROPIC_API_KEY'] = 'sk-test-fake-key'
      Chat::Claude.instance_variable_set(:@client, nil)
      ex.run
    ensure
      ENV.delete('ANTHROPIC_API_KEY')
      Chat::Claude.instance_variable_set(:@client, nil)
    end

    def stub_response(text, usage: nil)
      block    = double('TextBlock', type: :text, text: text)
      response = double('Message', content: [block])
      allow(response).to receive(:respond_to?).with(:usage).and_return(!usage.nil?)
      allow(response).to receive(:usage).and_return(usage)
      messages = double('Messages')
      allow(messages).to receive(:create).and_return(response)
      client = double('Client', messages: messages)
      allow(Anthropic::Client).to receive(:new).and_return(client)
      messages
    end

    it 'returns :unavailable when no API key is set' do
      ENV.delete('ANTHROPIC_API_KEY')
      result = Chat::Claude.respond(message: 'hi')
      expect(result.status).to eq(:unavailable)
    end

    it 'returns :empty for blank message' do
      result = Chat::Claude.respond(message: '   ')
      expect(result.status).to eq(:empty)
    end

    it 'returns :ok with reply text + model on success' do
      stub_response('Sure — the article argues that TUIs win on focus.')
      result = Chat::Claude.respond(
        message: 'What is this about?',
        context: { title: 'TUIs are back', excerpt: 'Lazygit and helix...' }
      )
      expect(result.status).to eq(:ok)
      expect(result.text).to include('TUIs win')
      expect(result.model).to eq(Chat::Claude::MODEL)
    end

    it 'includes the page context in the system prompt' do
      captured = nil
      messages = stub_response('ok')
      allow(messages).to receive(:create) do |args|
        captured = args[:system_]
        block = double('TextBlock', type: :text, text: 'ok')
        resp  = double('Message', content: [block])
        allow(resp).to receive(:respond_to?).with(:usage).and_return(false)
        resp
      end

      Chat::Claude.respond(
        message: 'sum it up',
        context: { url: '/article/abc', title: 'Why CUDA won', excerpt: 'NVIDIA built CUDA in 2007.' }
      )
      expect(captured).to include('/article/abc')
      expect(captured).to include('Why CUDA won')
      expect(captured).to include('NVIDIA built CUDA in 2007.')
    end

    it 'caps the page excerpt at MAX_CONTEXT_CHARS' do
      captured = nil
      messages = stub_response('ok')
      allow(messages).to receive(:create) do |args|
        captured = args[:system_]
        block = double('TextBlock', type: :text, text: 'ok')
        resp  = double('Message', content: [block])
        allow(resp).to receive(:respond_to?).with(:usage).and_return(false)
        resp
      end

      huge = 'x' * (Chat::Claude::MAX_CONTEXT_CHARS + 5_000)
      Chat::Claude.respond(message: 'q', context: { excerpt: huge })

      # The system prompt has a fixed prefix; the excerpt portion alone
      # is bounded by MAX_CONTEXT_CHARS.
      excerpt_in_prompt = captured.sub(/.*Excerpt:\n/m, '').strip
      expect(excerpt_in_prompt.length).to be <= Chat::Claude::MAX_CONTEXT_CHARS
    end

    it 'caps the user message at MAX_MESSAGE_CHARS' do
      captured_messages = nil
      messages = stub_response('ok')
      allow(messages).to receive(:create) do |args|
        captured_messages = args[:messages]
        block = double('TextBlock', type: :text, text: 'ok')
        resp  = double('Message', content: [block])
        allow(resp).to receive(:respond_to?).with(:usage).and_return(false)
        resp
      end

      huge = 'q' * (Chat::Claude::MAX_MESSAGE_CHARS + 1_000)
      Chat::Claude.respond(message: huge)

      expect(captured_messages.last[:content].length).to eq(Chat::Claude::MAX_MESSAGE_CHARS)
      expect(captured_messages.last[:role]).to eq('user')
    end

    it 'forwards prior history (capped to MAX_HISTORY_TURNS pairs) before the new user message' do
      captured = nil
      messages = stub_response('ok')
      allow(messages).to receive(:create) do |args|
        captured = args[:messages]
        block = double('TextBlock', type: :text, text: 'ok')
        resp  = double('Message', content: [block])
        allow(resp).to receive(:respond_to?).with(:usage).and_return(false)
        resp
      end

      # 30 prior messages — should be trimmed to MAX_HISTORY_TURNS * 2 = 16
      history = 30.times.map { |i| { role: i.even? ? 'user' : 'assistant', content: "msg #{i}" } }
      Chat::Claude.respond(message: 'next', history: history)

      expect(captured.length).to eq(Chat::Claude::MAX_HISTORY_TURNS * 2 + 1)
      expect(captured.last).to eq(role: 'user', content: 'next')
    end

    it 'drops malformed history entries (unknown role / blank content)' do
      captured = nil
      messages = stub_response('ok')
      allow(messages).to receive(:create) do |args|
        captured = args[:messages]
        block = double('TextBlock', type: :text, text: 'ok')
        resp  = double('Message', content: [block])
        allow(resp).to receive(:respond_to?).with(:usage).and_return(false)
        resp
      end

      Chat::Claude.respond(
        message: 'next',
        history: [
          { role: 'user',      content: 'real message' },
          { role: 'system',    content: 'should be dropped' },
          { role: 'assistant', content: '' },
          { 'role' => 'assistant', 'content' => 'string-keyed entry' }
        ]
      )

      roles = captured.map { |m| m[:role] }
      contents = captured.map { |m| m[:content] }
      expect(roles).to eq(%w[user assistant user])
      expect(contents).to eq(['real message', 'string-keyed entry', 'next'])
    end

    it 'returns :error on Anthropic SDK errors' do
      messages = double('Messages')
      err = Class.new(Anthropic::Errors::APIError) do
        def initialize(message); @message = message; end
        def message; @message; end
      end
      allow(messages).to receive(:create).and_raise(err.new('rate limit hit'))
      client = double('Client', messages: messages)
      allow(Anthropic::Client).to receive(:new).and_return(client)

      result = Chat::Claude.respond(message: 'hi')
      expect(result.status).to eq(:error)
      expect(result.error).to include('rate limit hit')
    end

    it 'pulls token usage off the response when present' do
      usage = double('Usage', input_tokens: 1_234, output_tokens: 56)
      stub_response('reply', usage: usage)

      result = Chat::Claude.respond(message: 'hi')
      expect(result.status).to eq(:ok)
      expect(result.usage).to eq(input_tokens: 1234, output_tokens: 56)
    end

    it 'returns :error when Claude returns an empty content block' do
      stub_response('   ')
      result = Chat::Claude.respond(message: 'hi')
      expect(result.status).to eq(:error)
      expect(result.error).to include('empty')
    end
  end
end
