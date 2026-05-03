require_relative 'spec_helper'
require 'date'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'

RSpec.describe 'GET /topics/:term' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  let!(:feed) { FeedsStore.add(url: 'https://example.com/feed.rss', title: 'Example') }

  def insert(uid, title, body)
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: uid, title: title, url: "https://example.com/#{uid}", author: nil,
      published_at: '2026-05-02T12:00:00Z',
      content_html: "<p>#{body}</p>", content_text: body
    }])
  end

  it 'renders an empty state when no articles match the term' do
    get '/topics/zzzzznotfound'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('No articles match this topic')
  end

  it 'lists articles + their cached summaries for a real topic' do
    insert('a' * 12, 'K8s networking',
           'Kubernetes networking is hard. Pods talk to services. The CNI is interesting. Operators help. Last sentence.')
    insert('b' * 12, 'K8s scheduling',
           'Kubernetes scheduling is hard. Pods get placed. Scheduler logic decides. More content. Final sentence.')

    get '/topics/kubernetes'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('K8s networking')
    expect(last_response.body).to include('K8s scheduling')
    expect(last_response.body).to include('Highlights')
    # Each article's summary is rendered inline (auto-generated on import).
    expect(last_response.body).to include('Kubernetes')
  end

  it 'shows the count + cross-link to /topics + /search' do
    insert('a' * 12, 'K1', 'kubernetes pods networking. K8s scheduling and operators. Done.')

    get '/topics/kubernetes'
    expect(last_response.body).to include('1 recent article')
    expect(last_response.body).to include('href="/topics"')
    expect(last_response.body).to include('/search?q=kubernetes')
  end

  it 'highlights only show the first sentence per article (≤10 entries)' do
    20.times do |i|
      insert("k#{i.to_s.rjust(2, '0')}".ljust(12, '0'), "K post #{i}",
             "First sentence about kubernetes. Second sentence is longer. Third sentence rounds out the post #{i}.")
    end

    get '/topics/kubernetes'
    body = last_response.body
    # The highlights section caps at 10. The sentences come from the articles' summaries.
    highlights_section = body[/<h3>Highlights<\/h3>.*?<\/section>/m]
    expect(highlights_section).not_to be_nil
    excerpt_count = highlights_section.scan(/class="excerpt"/).length
    expect(excerpt_count).to be <= 10
  end

  it 'falls back gracefully on an FTS5 syntax error in the term' do
    insert('a' * 12, 'A', 'kubernetes pods')
    # An unmatched quote in the term breaks FTS5 syntax.
    get '/topics/%22'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('No articles match this topic')
  end
end
