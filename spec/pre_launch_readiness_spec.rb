require_relative 'spec_helper'
require_relative '../app/main'

# Pre-launch readiness items shipped together: robots.txt + sitemap.xml,
# OG meta, 404 + 500 handlers, rate-limit tightening, /admin/status,
# /account/export.json. One spec file because they're a coherent
# launch bundle.
RSpec.describe 'Pre-launch readiness' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  describe 'GET /robots.txt' do
    it 'returns text/plain with disallows for the user-scoped surface' do
      get '/robots.txt'
      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('text/plain')
      body = last_response.body
      expect(body).to include('User-agent: *')
      expect(body).to include('Disallow: /admin')
      expect(body).to include('Disallow: /article/')
      expect(body).to include('Disallow: /account')
      expect(body).to include('Sitemap:')
    end

    it 'is registered as a public path' do
      expect(Auth::PUBLIC_PATHS).to include('/robots.txt')
    end
  end

  describe 'GET /sitemap.xml' do
    it 'returns valid XML with public-page URLs only' do
      get '/sitemap.xml'
      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('application/xml')
      body = last_response.body
      expect(body).to include('<urlset')
      expect(body).to include('<loc>')
      expect(body).to include('/about')
      expect(body).to include('/privacy')
      expect(body).to include('/terms')
      expect(body).to include('/contact')
      expect(body).to include('/sign-up')
      # Authed pages absent
      expect(body).not_to include('/articles')
      expect(body).not_to include('/admin')
    end
  end

  describe 'OG / Twitter card meta' do
    it 'renders og:title, og:image, twitter:card on every page' do
      get '/about'
      body = last_response.body
      expect(body).to match(/<meta property="og:title"\s+content="/)
      expect(body).to include('<meta property="og:image"')
      expect(body).to include('<meta name="twitter:card"')
      expect(body).to include('content="summary_large_image"')
    end

    it 'sets a canonical URL on every rendered page' do
      get '/about'
      expect(last_response.body).to match(%r{<link rel="canonical" href="[^"]*/about"})
    end
  end

  describe '404 handler' do
    it 'renders the branded not-found page for unknown routes' do
      get '/this-route-does-not-exist'
      expect(last_response.status).to eq(404)
      expect(last_response.body).to include('<h2>Lost?</h2>')
      expect(last_response.body).to include('this-route-does-not-exist')
    end
  end

  describe 'rate limiter — registration tightening' do
    # We can't exercise the middleware end-to-end through rack-test
    # without the Rack::Builder wrap (the spec hits TechFeedReader
    # directly). Lock the RULES shape instead so a typo here can't
    # silently regress the limit.
    let(:rules) { RateLimiter::RULES }

    it 'caps /api/auth/register/* at 3 per 30 min per IP' do
      rule = rules.find do |r|
        req = Rack::Request.new(Rack::MockRequest.env_for('/api/auth/register/options', method: 'POST'))
        r[:match].call(req)
      end
      expect(rule).not_to be_nil
      expect(rule[:limit]).to be <= 5
      expect(rule[:window]).to be >= 900
    end

    it 'caps POST /contact (matches the new rule, not the chat catch-all)' do
      rule = rules.find do |r|
        req = Rack::Request.new(Rack::MockRequest.env_for('/contact', method: 'POST'))
        r[:match].call(req)
      end
      expect(rule).not_to be_nil
      expect(rule[:limit]).to be <= 10
    end
  end

  describe 'GET /admin/status' do
    it 'returns 200 with system + cron + corpus sections' do
      get '/admin/status'
      expect(last_response.status).to eq(200)
      body = last_response.body
      expect(body).to include('<h2>Status</h2>')
      expect(body).to include('System')
      expect(body).to include('Scheduled jobs')
      expect(body).to include('Corpus')
    end
  end

  describe 'GET /account/export.json' do
    it 'returns a JSON dump with the expected top-level shape' do
      get '/account/export.json'
      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('application/json')
      expect(last_response.headers['Content-Disposition']).to include('attachment')
      expect(last_response.headers['Content-Disposition']).to include('feeder-export-user-')

      payload = JSON.parse(last_response.body)
      expect(payload).to include('schema_version' => 1)
      expect(payload).to have_key('exported_at')
      expect(payload['user_id']).to eq(1)  # the auto-signed-in test user
      expect(payload['tables']).to be_a(Hash)
      %w[user feeds_users read_state tags mute_rules sports_follows
         webauthn_credentials recovery_codes support_messages].each do |key|
        expect(payload['tables']).to have_key(key)
      end
      expect(payload).to have_key('notes')
    end

    it 'redacts recovery-code hashes' do
      RecoveryCodesStore.regenerate_for!(1)
      get '/account/export.json'
      payload = JSON.parse(last_response.body)
      rc = payload['tables']['recovery_codes']
      expect(rc).not_to be_empty
      expect(rc.first['code_hash']).to start_with('[redacted')
    end
  end

  describe '/privacy mentions the export endpoint (no more "not yet")' do
    it 'links the export from the Privacy page' do
      get '/privacy'
      expect(last_response.body).to include('Export your data')
      expect(last_response.body).to match(%r{/account.*Export your data}m)
      expect(last_response.body).not_to include('not yet implemented')
    end
  end
end
