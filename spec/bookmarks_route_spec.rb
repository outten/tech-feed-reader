require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/read_state_store'
require_relative '../app/users_store'

# Dedicated bookmarks surface. /articles already accepts
# ?state=bookmarked, but /bookmarks is the discoverable page-with-
# its-own-empty-state. Also asserts cross-user isolation: bookmarks
# saved by user 2 are invisible to user 1.

RSpec.describe 'GET /bookmarks' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  let!(:feed) { FeedsStore.add(url: 'https://example.com/rss', title: 'Example') }

  def insert(uid, title, day_offset = 0)
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: uid, title: title, url: "https://example.com/#{uid}", author: nil,
      published_at: (Time.now - day_offset * 86_400).utc.iso8601,
      content_html: "<p>#{title}</p>", content_text: title
    }])
    ArticlesStore.find_by_uid(uid)
  end

  describe 'empty state' do
    it 'renders a friendly empty state when the user has saved nothing' do
      get '/bookmarks'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('★ Bookmarks')
      expect(last_response.body).to include('No bookmarks yet')
      expect(last_response.body).to include('☆ Bookmark')
    end

    it 'renders the empty state even when the user has plenty of unread (just none bookmarked)' do
      5.times { |i| insert("u#{i}".ljust(12, '0'), "Unread #{i}") }
      get '/bookmarks'
      expect(last_response.body).to include('No bookmarks yet')
      expect(last_response.body).not_to include('Unread 0')
    end
  end

  describe 'populated' do
    it 'lists every article the current user has bookmarked, newest first' do
      a = insert('aaaaaaaaaaaa', 'Older', 5)
      b = insert('bbbbbbbbbbbb', 'Newer', 1)
      ReadStateStore.mark_bookmarked(1, a['id'], value: true)
      ReadStateStore.mark_bookmarked(1, b['id'], value: true)

      get '/bookmarks'
      body = last_response.body
      expect(body).to include('Newer')
      expect(body).to include('Older')
      # Newer appears before Older — chronological desc by published_at.
      expect(body.index('Newer')).to be < body.index('Older')
    end

    it 'omits articles the user un-bookmarked' do
      a = insert('aaaaaaaaaaaa', 'Kept')
      b = insert('bbbbbbbbbbbb', 'Dropped')
      ReadStateStore.mark_bookmarked(1, a['id'], value: true)
      ReadStateStore.mark_bookmarked(1, b['id'], value: true)
      ReadStateStore.mark_bookmarked(1, b['id'], value: false)

      get '/bookmarks'
      expect(last_response.body).to include('Kept')
      expect(last_response.body).not_to include('Dropped')
    end
  end

  describe 'cross-user isolation (Phase A2)' do
    let!(:kate) { UsersStore.create(username: 'kate') }

    it "does not surface another user's bookmarks" do
      a = insert('aaaaaaaaaaaa', "Kate's pick")
      ReadStateStore.mark_bookmarked(kate['id'], a['id'], value: true)

      get '/bookmarks'
      expect(last_response.body).to include('No bookmarks yet')
      expect(last_response.body).not_to include("Kate's pick")
    end
  end

  describe 'header nav link' do
    it 'renders ★ Bookmarks between Articles and Podcasts' do
      get '/articles'
      body = last_response.body
      expect(body).to include('href="/bookmarks"')
      expect(body).to match(/&#9733; Bookmarks|★ Bookmarks/)
      # Order: Articles → Bookmarks → Podcasts.
      articles_at  = body.index('href="/articles"')
      bookmarks_at = body.index('href="/bookmarks"')
      podcasts_at  = body.index('href="/podcasts"')
      expect(articles_at).to be < bookmarks_at
      expect(bookmarks_at).to be < podcasts_at
    end

    it 'marks the Bookmarks link active on /bookmarks' do
      get '/bookmarks'
      expect(last_response.body).to match(/href="\/bookmarks"\s+class="active"/)
    end
  end
end
