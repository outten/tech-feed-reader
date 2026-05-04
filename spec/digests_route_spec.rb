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
    DigestStore.create(Digests::Result.new(
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
end
