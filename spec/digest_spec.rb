require_relative 'spec_helper'
require_relative '../app/digest'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/read_state_store'
require_relative '../app/summary_store'

RSpec.describe Digest do
  let(:now) { Time.utc(2026, 5, 3, 10, 0, 0) }

  def add_article(feed_id:, uid:, title:, hours_ago:, content_text: 'body text', audio_url: nil)
    published = (now - hours_ago * 3600).iso8601
    ArticlesStore.import(feed_id: feed_id, entries: [{
      uid: uid, title: title, url: "https://example.com/#{uid}",
      author: nil, published_at: published,
      content_html: "<p>#{content_text}</p>", content_text: content_text,
      audio_url: audio_url, audio_mime_type: nil, audio_duration_seconds: nil
    }])
    ArticlesStore.find_by_uid(uid)
  end

  describe '.compose' do
    it 'returns a zero-count Result when no unread articles fall in the window' do
      result = Digest.compose(now: now)
      expect(result.count).to eq(0)
      expect(result.subject).to include('no new articles')
      expect(result.text).to include('Nothing new')
      expect(result.html).to include('No new articles')
    end

    it 'includes only UNREAD articles within the window' do
      feed = FeedsStore.add(url: 'https://x.com/rss', title: 'Example Feed')

      kept    = add_article(feed_id: feed['id'], uid: 'aaaaaaaaaaaa', title: 'Fresh + unread',  hours_ago: 2)
      _read   = add_article(feed_id: feed['id'], uid: 'bbbbbbbbbbbb', title: 'Fresh + read',    hours_ago: 4)
      _stale  = add_article(feed_id: feed['id'], uid: 'cccccccccccc', title: 'Stale + unread',  hours_ago: 48)

      ReadStateStore.mark_read(ArticlesStore.find_by_uid('bbbbbbbbbbbb')['id'], read: true)

      result = Digest.compose(window_hours: 24, now: now)
      expect(result.count).to eq(1)
      expect(result.text).to include('Fresh + unread')
      expect(result.text).not_to include('Fresh + read')
      expect(result.text).not_to include('Stale + unread')
      expect(result.html).to include(kept['url'])
    end

    it 'orders newest first within the window' do
      feed = FeedsStore.add(url: 'https://x.com/rss', title: 'Example Feed')
      add_article(feed_id: feed['id'], uid: 'older0000001', title: 'Older one', hours_ago: 10)
      add_article(feed_id: feed['id'], uid: 'newer0000002', title: 'Newer one', hours_ago: 1)

      result = Digest.compose(now: now)
      newer_idx = result.text.index('Newer one')
      older_idx = result.text.index('Older one')
      expect(newer_idx).to be < older_idx
    end

    it 'honours the limit argument' do
      feed = FeedsStore.add(url: 'https://x.com/rss', title: 'Example Feed')
      6.times { |i| add_article(feed_id: feed['id'], uid: "art#{i.to_s.rjust(9, '0')}", title: "Article #{i}", hours_ago: i + 1) }

      result = Digest.compose(limit: 3, now: now)
      expect(result.count).to eq(3)
    end

    it 'prefers LLM summary, then extractive, then content excerpt' do
      feed = FeedsStore.add(url: 'https://x.com/rss', title: 'Example Feed')
      llm_art   = add_article(feed_id: feed['id'], uid: 'llmllmllmlll', title: 'LLM article',   hours_ago: 1, content_text: 'long body that should not show')
      ext_art   = add_article(feed_id: feed['id'], uid: 'extextextext', title: 'Extr article',  hours_ago: 2, content_text: 'long body that should not show')
      raw_art   = add_article(feed_id: feed['id'], uid: 'rawrawrawraw', title: 'Raw article',   hours_ago: 3, content_text: 'just the raw content excerpt for fallback display')

      SummaryStore.upsert(llm_art['id'], llm: 'llm summary preferred', llm_model: 'claude-x')
      SummaryStore.upsert(ext_art['id'], extractive: 'extractive summary used')
      # raw_art has no summary row → falls back to content_text excerpt

      result = Digest.compose(now: now)
      expect(result.text).to include('llm summary preferred')
      expect(result.text).to include('extractive summary used')
      expect(result.text).to include('just the raw content excerpt')
      expect(result.text).not_to include('long body that should not show')
    end

    it 'tags podcast episodes (audio_url present) with a 🎧 marker in text and PODCAST badge in HTML' do
      feed = FeedsStore.add(url: 'https://x.com/rss', title: 'Example Pod')
      add_article(feed_id: feed['id'], uid: 'podpodpodpod1', title: 'Episode 5',
                  hours_ago: 1, audio_url: 'https://cdn.example.com/ep5.mp3')

      result = Digest.compose(now: now)
      expect(result.text).to include('🎧 podcast')
      expect(result.html).to include('PODCAST')
    end

    it 'HTML-escapes title, feed name, and summary so a malicious title cannot break out' do
      feed = FeedsStore.add(url: 'https://x.com/rss', title: 'Feed <bad>')
      art = add_article(feed_id: feed['id'], uid: 'xssxssxssxss', title: '<script>alert(1)</script>', hours_ago: 1)
      SummaryStore.upsert(art['id'], extractive: 'a "tricky" & summary <span>')

      result = Digest.compose(now: now)
      expect(result.html).to include('&lt;script&gt;alert(1)&lt;/script&gt;')
      expect(result.html).to include('Feed &lt;bad&gt;')
      expect(result.html).to include('&quot;tricky&quot;')
      expect(result.html).not_to include('<script>alert(1)</script>')
      expect(result.html).not_to include('<span>')
    end

    it 'subject reflects count + day; text + html include "last Nh"' do
      feed = FeedsStore.add(url: 'https://x.com/rss', title: 'Example')
      add_article(feed_id: feed['id'], uid: 'aaaaaaaaaaa1', title: 'A', hours_ago: 1)
      add_article(feed_id: feed['id'], uid: 'aaaaaaaaaaa2', title: 'B', hours_ago: 2)
      add_article(feed_id: feed['id'], uid: 'aaaaaaaaaaa3', title: 'C', hours_ago: 3)

      result = Digest.compose(window_hours: 12, now: now)
      expect(result.subject).to include('3 new articles')
      expect(result.subject).to match(/\(.*May.*3\)/)
      expect(result.text).to include('last 12h')
      expect(result.html).to include('Last 12 hours')
    end
  end

  describe '.query_unread' do
    it 'returns the same shape compose uses (joins feed title + summaries)' do
      feed = FeedsStore.add(url: 'https://x.com/rss', title: 'Example Feed')
      art  = add_article(feed_id: feed['id'], uid: 'qqqqqqqqqqqq', title: 'Q', hours_ago: 1)
      SummaryStore.upsert(art['id'], llm: 'L', extractive: 'E')

      rows = Digest.query_unread(window_hours: 24, limit: 5, now: now)
      expect(rows.length).to eq(1)
      row = rows.first
      expect(row['title']).to eq('Q')
      expect(row['feed_title']).to eq('Example Feed')
      expect(row['summary_llm']).to eq('L')
      expect(row['summary_extractive']).to eq('E')
    end
  end
end
