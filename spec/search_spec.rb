require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'

RSpec.describe '/search' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  let!(:feed) { FeedsStore.add(url: 'https://example.com/feed.rss', title: 'Example') }
  let!(:articles) do
    ArticlesStore.import(feed_id: feed['id'], entries: [
      { uid: 'a' * 12, title: 'Ruby on Rails', url: 'https://example.com/a', author: nil,
        published_at: '2026-05-02T12:00:00Z', content_html: '<p>x</p>',
        content_text: 'A web framework written in Ruby.' },
      { uid: 'b' * 12, title: 'JavaScript fun', url: 'https://example.com/b', author: nil,
        published_at: '2026-05-01T12:00:00Z', content_html: '<p>y</p>',
        content_text: 'A scripting language for browsers.' },
      { uid: 'c' * 12, title: 'Database tips', url: 'https://example.com/c', author: nil,
        published_at: '2026-04-30T12:00:00Z', content_html: '<p>z</p>',
        content_text: 'Indexes, queries, and Ruby ORM patterns.' }
    ])
  end

  it 'renders the empty form when no query is given' do
    get '/search'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Search')
    expect(last_response.body).not_to include('Results for')
  end

  it 'returns matching articles for a single-term query' do
    get '/search?q=ruby'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Ruby on Rails')
    expect(last_response.body).to include('Database tips')
    expect(last_response.body).not_to include('JavaScript fun')
  end

  it 'highlights matches via FTS5 snippet' do
    get '/search?q=framework'
    expect(last_response.body).to include('<mark>framework</mark>')
  end

  it 'shows a no-results notice when nothing matches' do
    get '/search?q=zzzzznotfound'
    expect(last_response.body).to include('No results')
  end

  it 'renders an error notice for malformed FTS5 queries' do
    skip 'FTS5-specific syntax error path; PG`s plainto_tsquery normalises bad input' if Database.adapter == :postgres
    get '/search?q=%22'   # bare quote → unterminated phrase
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Query syntax error')
  end

  it 'escapes the query in the page (no XSS via reflected ?q)' do
    get '/search?q=%3Cscript%3Ealert%281%29%3C%2Fscript%3E'
    expect(last_response.body).not_to include('<script>alert(1)</script>')
    expect(last_response.body).to include('&lt;script&gt;')
  end

  # Phase 3 polish (2026-05-12) — pre-search "Try a query" panel +
  # card-style results matching the /articles list.
  it 'shows the "Try a query" suggestion chips when there is no query' do
    get '/search'
    expect(last_response.body).to include('Try a query')
    expect(last_response.body).to include('search-suggestion-chip')
    # Spot-check one of the chips is linked to /search with the term.
    expect(last_response.body).to match(%r{<a class="search-suggestion-chip" href="/search\?q=ai"})
  end

  it 'omits the "Try a query" panel once a query is present' do
    get '/search?q=ruby'
    expect(last_response.body).not_to include('Try a query')
  end

  it 'renders result rows as cards with title + excerpt + meta + kind icon' do
    get '/search?q=framework'
    expect(last_response.body).to include('news-row-main')
    expect(last_response.body).to include('search-excerpt')
    expect(last_response.body).to include('news-kind-icon')
  end
end
