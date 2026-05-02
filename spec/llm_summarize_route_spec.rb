require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/summary_store'
require_relative '../app/summarizer/claude'

RSpec.describe '/article/:uid/summarize/llm' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  let(:feed) { FeedsStore.add(url: 'https://example.com/feed.rss') }
  let(:article) do
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: 'a' * 12, title: 'Test', url: 'https://example.com/a', author: nil,
      published_at: '2026-05-02T12:00:00Z',
      content_html: '<p>hi</p>',
      content_text: 'A non-trivial article body about kubernetes networking and operators.'
    }])
    ArticlesStore.find_by_uid('a' * 12)
  end

  describe 'with API key configured' do
    around(:each) do |ex|
      ENV['ANTHROPIC_API_KEY'] = 'sk-test-fake'
      Summarizer::Claude.instance_variable_set(:@client, nil)
      ex.run
    ensure
      ENV.delete('ANTHROPIC_API_KEY')
      Summarizer::Claude.instance_variable_set(:@client, nil)
    end

    it 'stores the LLM summary and redirects with notice=llm-summarized' do
      block    = double('TextBlock', type: :text, text: 'Tight LLM summary text.')
      response = double('Message', content: [block])
      messages = double('Messages')
      allow(messages).to receive(:create).and_return(response)
      client = double('Client', messages: messages)
      allow(Anthropic::Client).to receive(:new).and_return(client)

      post "/article/#{article['uid']}/summarize/llm"
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to include('notice=llm-summarized')
      expect(last_response.headers['Location']).to include('model=claude-opus-4-7')

      stored = SummaryStore.find(article['id'])
      expect(stored['llm']).to eq('Tight LLM summary text.')
      expect(stored['llm_model']).to eq(Summarizer::Claude::MODEL)
    end

    it 'preserves existing extractive summary on LLM upsert (field merge)' do
      SummaryStore.upsert(article['id'], extractive: 'Already-stored extractive.')

      block = double('TextBlock', type: :text, text: 'New LLM.')
      messages = double('Messages')
      allow(messages).to receive(:create).and_return(double('Message', content: [block]))
      allow(Anthropic::Client).to receive(:new).and_return(double('Client', messages: messages))

      post "/article/#{article['uid']}/summarize/llm"
      stored = SummaryStore.find(article['id'])
      expect(stored['extractive']).to eq('Already-stored extractive.')
      expect(stored['llm']).to eq('New LLM.')
    end

    it 'redirects with error=llm-failed when the SDK raises' do
      messages = double('Messages')
      allow(messages).to receive(:create).and_raise(StandardError, 'kaboom')
      allow(Anthropic::Client).to receive(:new).and_return(double('Client', messages: messages))

      post "/article/#{article['uid']}/summarize/llm"
      expect(last_response.headers['Location']).to include('error=llm-failed')
      expect(last_response.headers['Location']).to include('kaboom')
    end
  end

  describe 'without API key' do
    before { ENV.delete('ANTHROPIC_API_KEY') }

    it 'redirects with error=llm-unavailable' do
      post "/article/#{article['uid']}/summarize/llm"
      expect(last_response.headers['Location']).to include('error=llm-unavailable')
    end

    it 'hides the "Summarize with Claude" button on /article/:uid' do
      get "/article/#{article['uid']}"
      expect(last_response.body).not_to include('Summarize with Claude')
    end
  end

  it '404s on an unknown uid' do
    post '/article/zzzzzzzzzzzz/summarize/llm'
    expect(last_response.status).to eq(404)
  end
end
