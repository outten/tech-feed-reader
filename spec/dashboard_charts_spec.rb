require_relative 'spec_helper'
require 'date'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/tags_store'
require_relative '../app/main'

RSpec.describe 'dashboard charts' do
  describe 'ArticlesStore.daily_counts' do
    let!(:feed) { FeedsStore.add(url: 'https://example.com/feed.rss') }

    def insert_article(uid, day_offset)
      published = (Date.today - day_offset).to_s + 'T12:00:00Z'
      ArticlesStore.import(feed_id: feed['id'], entries: [{
        uid: uid, title: "T#{uid}", url: "https://example.com/#{uid}", author: nil,
        published_at: published,
        content_html: '<p>x</p>', content_text: 'x'
      }])
    end

    it 'returns one row per day in the window, gap-filled to zero' do
      insert_article('a' * 12, 0)
      insert_article('b' * 12, 0)
      insert_article('c' * 12, 5)

      counts = ArticlesStore.daily_counts(days: 7)
      expect(counts.length).to eq(7)
      expect(counts.last[:day]).to  eq(Date.today.to_s)
      expect(counts.last[:count]).to eq(2)
      expect(counts[1][:day]).to eq((Date.today - 5).to_s)
      expect(counts[1][:count]).to eq(1)
      expect(counts[3][:count]).to eq(0)  # a gap day
    end

    it 'excludes articles older than the window' do
      insert_article('a' * 12, 100)
      counts = ArticlesStore.daily_counts(days: 30)
      expect(counts.sum { |c| c[:count] }).to eq(0)
    end
  end

  describe 'ArticlesStore.counts_by_feed' do
    it 'returns feeds in descending count order, with zero-count feeds at the bottom' do
      a = FeedsStore.add(url: 'https://a.example.com/rss', title: 'A')
      b = FeedsStore.add(url: 'https://b.example.com/rss', title: 'B')
      c = FeedsStore.add(url: 'https://c.example.com/rss', title: 'C')

      ArticlesStore.import(feed_id: a['id'], entries: 3.times.map { |i|
        { uid: "a#{i}".ljust(12, '0'), title: 'x', url: "https://example.com/a#{i}",
          author: nil, published_at: '2026-05-02T12:00:00Z',
          content_html: '<p>x</p>', content_text: 'x' }
      })
      ArticlesStore.import(feed_id: b['id'], entries: [{
        uid: 'b' * 12, title: 'y', url: 'https://example.com/b', author: nil,
        published_at: '2026-05-02T12:00:00Z', content_html: '<p>x</p>', content_text: 'x'
      }])

      ranked = ArticlesStore.counts_by_feed(limit: 10).map { |r| [r['title'], r['c']] }
      expect(ranked).to eq([['A', 3], ['B', 1], ['C', 0]])
    end
  end

  describe 'TagsStore.top_in_window' do
    let!(:feed) { FeedsStore.add(url: 'https://example.com/feed.rss') }

    def insert_article(uid, body, day_offset = 0)
      ArticlesStore.import(feed_id: feed['id'], entries: [{
        uid: uid, title: 'x', url: "https://example.com/#{uid}", author: nil,
        published_at: (Date.today - day_offset).to_s + 'T12:00:00Z',
        content_html: '<p>x</p>', content_text: body
      }])
    end

    it 'counts articles with the tag inside the window only' do
      ai   = TagsStore.add(name: 'ai',   match_kind: 'keyword', match_value: 'ai')
      rust = TagsStore.add(name: 'rust', match_kind: 'keyword', match_value: 'rust')

      insert_article('a' * 12, 'machine learning ai future',     0)
      insert_article('b' * 12, 'ai is everywhere',               2)
      insert_article('c' * 12, 'rust borrow checker',             1)
      insert_article('d' * 12, 'old ai story',                   30)  # outside window

      result = TagsStore.top_in_window(days: 7, limit: 10).map { |r| [r['name'], r['count']] }
      expect(result).to contain_exactly(['ai', 2], ['rust', 1])
    end

    it 'returns [] when nothing matches in the window' do
      expect(TagsStore.top_in_window(days: 7)).to eq([])
    end
  end

  describe 'GET /dashboard' do
    include Rack::Test::Methods
    def app; TechFeedReader; end

    it 'renders the chart canvas and Chart.js inclusion when there are articles' do
      feed = FeedsStore.add(url: 'https://example.com/feed.rss')
      ArticlesStore.import(feed_id: feed['id'], entries: [{
        uid: 'a' * 12, title: 'x', url: 'https://example.com/a', author: nil,
        published_at: Date.today.to_s + 'T12:00:00Z',
        content_html: '<p>x</p>', content_text: 'something to summarize'
      }])

      get '/dashboard'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('id="dailyChart"')
      expect(last_response.body).to include('chart.umd.min.js')
      expect(last_response.body).to include('Most active feeds')
    end

    # Regression: the Activity chart was blank on Turbo Drive navigation
    # and only painted after a hard refresh. The fix listens for
    # turbo:load + destroys any prior Chart bound to the canvas before
    # re-creating, mirroring public/chat-widget.js's pattern.
    it 'wires turbo:load + destroy-prior-Chart so the chart re-paints on Turbo navigation' do
      feed = FeedsStore.add(url: 'https://example.com/feed.rss')
      ArticlesStore.import(feed_id: feed['id'], entries: [{
        uid: 'a' * 12, title: 'x', url: 'https://example.com/a', author: nil,
        published_at: Date.today.to_s + 'T12:00:00Z',
        content_html: '<p>x</p>', content_text: 'x'
      }])
      get '/dashboard'
      expect(last_response.body).to include("addEventListener('turbo:load'")
      expect(last_response.body).to include('Chart.getChart')
    end

    it 'omits the chart entirely when there are no articles' do
      get '/dashboard'
      expect(last_response.body).not_to include('id="dailyChart"')
      expect(last_response.body).not_to include('chart.umd.min.js')
    end
  end
end
