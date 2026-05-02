require_relative 'spec_helper'
require_relative '../app/summarizer/claude'

RSpec.describe Summarizer::Claude do
  describe '.available?' do
    it 'is false when ANTHROPIC_API_KEY is unset' do
      ENV.delete('ANTHROPIC_API_KEY')
      expect(Summarizer::Claude.available?).to be(false)
    end

    it 'is true when ANTHROPIC_API_KEY is set' do
      ENV['ANTHROPIC_API_KEY'] = 'sk-test-fake-key'
      expect(Summarizer::Claude.available?).to be(true)
    ensure
      ENV.delete('ANTHROPIC_API_KEY')
    end
  end

  describe '.summarize' do
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
      response = double('Message', content: [block])
      messages = double('Messages')
      allow(messages).to receive(:create).and_return(response)
      client = double('Client', messages: messages)
      allow(Anthropic::Client).to receive(:new).and_return(client)
    end

    it 'returns :unavailable when no API key is set' do
      ENV.delete('ANTHROPIC_API_KEY')
      result = Summarizer::Claude.summarize(title: 'T', content_text: 'A long enough body to summarize.')
      expect(result.status).to eq(:unavailable)
    end

    it 'returns :empty for blank content_text' do
      result = Summarizer::Claude.summarize(title: 'T', content_text: '   ')
      expect(result.status).to eq(:empty)
    end

    it 'returns :ok with text + model on a successful call' do
      stub_response("This is a tight three-sentence summary. It captures the key points. The end.")
      result = Summarizer::Claude.summarize(
        title:        'Why TUIs are back',
        content_text: 'Terminal UIs are seeing a renaissance. Tools like lazygit and helix are rivaling GUIs.'
      )
      expect(result.status).to eq(:ok)
      expect(result.text).to include('three-sentence')
      expect(result.model).to eq(Summarizer::Claude::MODEL)
    end

    it 'truncates very long bodies to MAX_CONTENT chars' do
      captured = nil
      messages = double('Messages')
      allow(messages).to receive(:create) do |args|
        captured = args[:messages].first[:content]
        block    = double('TextBlock', type: :text, text: 'ok')
        double('Message', content: [block])
      end
      client = double('Client', messages: messages)
      allow(Anthropic::Client).to receive(:new).and_return(client)

      huge = 'x' * (Summarizer::Claude::MAX_CONTENT + 1000)
      Summarizer::Claude.summarize(title: 'big', content_text: huge)

      # The user message includes "Title: big\n\n" prefix, so the body
      # portion alone is bounded by MAX_CONTENT.
      body_only = captured.sub(/\ATitle: big\n\n/, '')
      expect(body_only.length).to eq(Summarizer::Claude::MAX_CONTENT)
    end

    it 'returns :error on Anthropic SDK errors' do
      messages = double('Messages')
      err = Class.new(Anthropic::Errors::APIError) do
        def initialize(message)
          @message = message
        end
        def message; @message; end
      end
      allow(messages).to receive(:create).and_raise(err.new('rate limit hit'))
      client = double('Client', messages: messages)
      allow(Anthropic::Client).to receive(:new).and_return(client)

      result = Summarizer::Claude.summarize(title: 'T', content_text: 'A long enough body to summarize.')
      expect(result.status).to eq(:error)
      expect(result.error).to include('rate limit hit')
    end

    it 'returns :error on unexpected exceptions (no raise)' do
      messages = double('Messages')
      allow(messages).to receive(:create).and_raise(StandardError, 'kaboom')
      client = double('Client', messages: messages)
      allow(Anthropic::Client).to receive(:new).and_return(client)

      result = Summarizer::Claude.summarize(title: 'T', content_text: 'A long enough body to summarize.')
      expect(result.status).to eq(:error)
      expect(result.error).to include('kaboom')
    end

    it 'returns :error when Claude returns an empty content block' do
      block    = double('TextBlock', type: :text, text: '   ')
      response = double('Message', content: [block])
      messages = double('Messages')
      allow(messages).to receive(:create).and_return(response)
      client = double('Client', messages: messages)
      allow(Anthropic::Client).to receive(:new).and_return(client)

      result = Summarizer::Claude.summarize(title: 'T', content_text: 'Some body.')
      expect(result.status).to eq(:error)
      expect(result.error).to include('empty')
    end
  end
end
