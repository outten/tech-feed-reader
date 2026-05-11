require_relative 'spec_helper'
require 'date'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'

RSpec.describe 'GET /topics' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  let!(:feed) { FeedsStore.add(url: 'https://example.com/feed.rss') }

  def insert(uid, title, body, day_offset = 0)
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: uid, title: title, url: "https://example.com/#{uid}", author: nil,
      published_at: (Date.today - day_offset).to_s + 'T12:00:00Z',
      content_html: "<p>#{body}</p>", content_text: body
    }])
  end

  it 'renders the empty state when no clusters surface in the window' do
    get '/topics'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('No topics surfaced')
  end

  it 'lists clusters with sample article links' do
    insert('a' * 12, 'K1', 'kubernetes networking and pods explained.')
    insert('b' * 12, 'K2', 'kubernetes scheduling and operators.')
    insert('c' * 12, 'K3', 'kubernetes scaling autoscaling.')

    get '/topics'
    expect(last_response.body).to include('kubernetes')
    expect(last_response.body).to match(/K1|K2|K3/)
    expect(last_response.body).to include('/topics/kubernetes')
  end

  it 'honours ?days= window selector (clamped to 7/14/30)' do
    insert('a' * 12, 'old',  'rust borrow checker memory safety.', 25)
    insert('b' * 12, 'old2', 'rust async tokio runtime.',           25)

    get '/topics?days=7'
    expect(last_response.body).to include('No topics surfaced')

    get '/topics?days=30'
    expect(last_response.body).to include('rust')
  end

  it 'falls back to the default 14-day window for unknown days values' do
    insert('a' * 12, 'A', 'rust borrow checker memory safety.')
    insert('b' * 12, 'B', 'rust async tokio runtime.')

    get '/topics?days=bogus'
    expect(last_response.body).to include('rust')
    expect(last_response.body).to include('class="active"')
    # The 14-day pill is the default-active one. The anchor carries
    # href + class + (now) a title= tooltip — assert each separately
    # so the regex doesn't break on attribute reordering / new attrs.
    expect(last_response.body).to match(/<a href="\?days=14"[^>]*class="active"[^>]*>last 14 days/)
  end

  it 'exposes Topics in the main nav' do
    get '/admin/dashboard'
    expect(last_response.body).to include('href="/topics"')
  end
end
