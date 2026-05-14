require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/digest_store'
require_relative '../app/digests'

RSpec.describe 'Digest routes' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  def stash(generated_at:, subject: 'Subj', count: 3, window: 24, html: '<div class="digest-items">stored fragment</div>')
    DigestStore.create(1, Digests::Result.new(
      subject: subject, text: 'TXT', html: html, count: count,
      window_hours: window, generated_at: generated_at
    ))
  end

  describe 'GET /digests' do
    it 'renders the empty state when no digests have been generated' do
      get '/digests'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('No digests yet')
      expect(last_response.body).to include('make digest')
    end

    it 'lists stored digests newest-first with subject + count + window' do
      stash(generated_at: Time.utc(2026, 5, 1, 7, 0, 0), subject: 'older one', count: 4,  window: 24)
      stash(generated_at: Time.utc(2026, 5, 4, 7, 0, 0), subject: 'newest one', count: 12, window: 12)

      get '/digests'
      expect(last_response.status).to eq(200)
      body = last_response.body
      expect(body).to include('newest one')
      expect(body).to include('older one')
      expect(body.index('newest one')).to be < body.index('older one')
      expect(body).to include('12h')   # window column
      expect(body).to include('>12<')  # count column (right-aligned cell)
    end

    it 'links each row to /digests/:id' do
      id = stash(generated_at: Time.utc(2026, 5, 4, 7, 0, 0), subject: 'My Digest')
      get '/digests'
      expect(last_response.body).to include(%(href="/digests/#{id}"))
    end

    it 'exposes Digests in the main nav' do
      get '/digests'
      expect(last_response.body).to include('href="/digests"')
    end
  end

  describe 'GET /digests/:id' do
    it 'renders the stored html_body inline' do
      id = stash(
        generated_at: Time.utc(2026, 5, 4, 7, 0, 0),
        subject: 'Detail Subject',
        html: '<div class="digest-items"><div class="digest-item">item one</div></div>'
      )
      get "/digests/#{id}"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('Detail Subject')
      expect(last_response.body).to include('item one')
      expect(last_response.body).to include('class="digest-items"')
    end

    it 'links back to the listing page' do
      id = stash(generated_at: Time.utc(2026, 5, 4, 7, 0, 0))
      get "/digests/#{id}"
      expect(last_response.body).to include('All digests')
      expect(last_response.body).to include('href="/digests"')
    end

    it '404s on unknown digest id' do
      get '/digests/99999'
      expect(last_response.status).to eq(404)
    end
  end

  describe 'POST /digests (manual trigger)' do
    def add_unread_article(uid:, hours_ago:)
      feed = FeedsStore.find_by_url('https://x.com/manualfeed') ||
             FeedsStore.add(url: 'https://x.com/manualfeed', title: 'Feed')
      ArticlesStore.import(feed_id: feed['id'], entries: [{
        uid: uid, title: "Article #{uid}",
        url: "https://x.com/#{uid}", author: nil,
        published_at: (Time.now.utc - hours_ago * 3600).iso8601,
        content_html: '<p>x</p>', content_text: 'x',
        audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
      }])
    end

    it 'composes + stores a digest and redirects to its detail page with the count' do
      add_unread_article(uid: 'manualart001', hours_ago: 2)
      add_unread_article(uid: 'manualart002', hours_ago: 4)

      expect { post '/digests' }.to change { DigestStore.count(1) }.by(1)
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to match(%r{/digests/\d+\?notice=generated&count=2})
    end

    it 'honours ?window_hours and ?limit overrides' do
      add_unread_article(uid: 'recentitem01', hours_ago: 5)
      add_unread_article(uid: 'oldfromweek1', hours_ago: 24 * 5)  # outside default 24h window

      post '/digests', { window_hours: '168', limit: '10' }
      expect(last_response.status).to eq(302)
      detail_id = last_response.headers['Location'][%r{/digests/(\d+)}, 1].to_i
      row = DigestStore.find(1, detail_id)
      expect(row['window_hours']).to eq(168)
      expect(row['article_count']).to eq(2)  # both fall inside the 7-day window
    end

    it 'falls back to the defaults when the params are non-numeric' do
      post '/digests', { window_hours: 'spaceship', limit: 'twenty' }
      detail_id = last_response.headers['Location'][%r{/digests/(\d+)}, 1].to_i
      row = DigestStore.find(1, detail_id)
      expect(row['window_hours']).to eq(Digests::DEFAULT_WINDOW_HOURS)
    end

    it 'clamps wildly large window_hours to a sane ceiling' do
      post '/digests', { window_hours: '99999' }
      detail_id = last_response.headers['Location'][%r{/digests/(\d+)}, 1].to_i
      expect(DigestStore.find(1, detail_id)['window_hours']).to be <= 720  # one month
    end

    it 'renders the Generate-now button on /digests' do
      get '/digests'
      expect(last_response.body).to include('action="/digests"')
      expect(last_response.body).to include('Generate now')
    end

    it 'includes a /digests link in /admin Sub-pages' do
      allow_any_instance_of(TechFeedReader).to receive(:sidekiq_stats).and_return(
        ok: true, enqueued: 0, scheduled: 0, retries: 0, dead: 0,
        processed: 0, failed: 0, workers: 0
      )
      get '/admin'
      expect(last_response.body).to include('href="/digests"')
      expect(last_response.body).to include('Generate now')
    end
  end
end
