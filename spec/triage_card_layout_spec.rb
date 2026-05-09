require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/triage/claude'
require_relative '../app/triage_store'

# STUFF.md #8 — triage page card layout. Each entry now renders
# as a vertical-card (.sports-article shape) rather than the old
# horizontal news-item row. New: inline article summary + the
# title links to the publisher in a new tab + "Open in app"
# affordance for the in-app reading view.

def seed_triage_with_article(uid:, title:, url:, content_text:, group: :must_read, rationale: 'Strong corpus match')
  feed = FeedsStore.find_by_url('https://x.com/triage-rss') ||
         FeedsStore.add(url: 'https://x.com/triage-rss', title: 'Triage feed', topic: 'general')
  ArticlesStore.import(feed_id: feed['id'], entries: [{
    uid: uid, title: title, url: url, author: 'Author',
    published_at: '2026-05-08T12:00:00Z',
    content_html: "<p>#{content_text}</p>", content_text: content_text,
    audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
  }])

  result = Triage::Claude::Result.new(
    status: :ok, model: 'claude-sonnet-4-6',
    must_read: group == :must_read ? [{ 'uid' => uid, 'rationale' => rationale }] : [],
    optional:  group == :optional  ? [{ 'uid' => uid, 'rationale' => rationale }] : [],
    skip:      group == :skip      ? [{ 'uid' => uid, 'rationale' => rationale }] : [],
    unread_count: 1, latency_ms: 100
  )
  TriageStore.create(result)
end

RSpec.describe 'GET /triage/:id card layout (STUFF.md #8)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'renders each entry as a vertical card with the .sports-article shape' do
    id = seed_triage_with_article(
      uid: 'triagecard01', title: 'Eagles win division',
      url: 'https://example.com/eagles', content_text: 'The Eagles clinched the NFC East with a decisive win.'
    )
    get "/triage/#{id}"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('class="sports-article triage-card')
    expect(last_response.body).to include('class="sports-article-title"')
  end

  it 'links the headline to the publisher URL in a new tab' do
    id = seed_triage_with_article(
      uid: 'triagecard02', title: 'External link test',
      url: 'https://publisher.example.com/article', content_text: 'body'
    )
    get "/triage/#{id}"
    expect(last_response.body).to match(%r{<a href="https://publisher\.example\.com/article"\s+target="_blank"\s+rel="noopener noreferrer"})
  end

  it 'renders the inline article summary (skim_summary_for fallback)' do
    id = seed_triage_with_article(
      uid: 'triagecard03', title: 'Has body',
      url: 'https://example.com/c', content_text: 'This is a meaningful article body that should appear in the inline summary.'
    )
    get "/triage/#{id}"
    expect(last_response.body).to include('class="sports-article-summary"')
    expect(last_response.body).to include('meaningful article body')
  end

  it 'renders the rationale with a "Why:" prefix' do
    id = seed_triage_with_article(
      uid: 'triagecard04', title: 'X', url: 'https://example.com/d', content_text: 'body',
      rationale: 'matches your bookmarked Ruby work'
    )
    get "/triage/#{id}"
    expect(last_response.body).to include('class="triage-rationale"')
    expect(last_response.body).to match(/<strong>Why:<\/strong>\s*matches your bookmarked Ruby work/)
  end

  it 'offers an "Open in app" affordance pointing at /article/<uid>' do
    id = seed_triage_with_article(
      uid: 'triagecard05', title: 'X', url: 'https://example.com/e', content_text: 'body'
    )
    get "/triage/#{id}"
    expect(last_response.body).to include('class="sports-article-in-app"')
    expect(last_response.body).to include('href="/article/triagecard05"')
    expect(last_response.body).to include('Open in app')
  end
end
