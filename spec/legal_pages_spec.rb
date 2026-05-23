require_relative 'spec_helper'
require_relative '../app/main'

# STUFF #62 — privacy + terms pages are public (reachable without
# sign-in) and linked from the footer. Lock the route shape, the
# public-paths registration, and a few key phrases so a future edit
# can't quietly delete the legal section.
RSpec.describe 'Public legal pages (STUFF #62)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  describe 'auth registration' do
    it 'registers /privacy + /terms as public paths' do
      expect(Auth::PUBLIC_PATHS).to include('/privacy')
      expect(Auth::PUBLIC_PATHS).to include('/terms')
    end
  end

  describe 'GET /privacy' do
    it 'returns 200 with the page header + key sections' do
      get '/privacy'
      expect(last_response.status).to eq(200)
      body = last_response.body
      expect(body).to include('<h2>Privacy</h2>')
      expect(body).to include('What we store')
      expect(body).to include("What we don't store")
      expect(body).to include('Third parties we send data to')
      expect(body).to include('Retention')
      expect(body).to include('Anthropic')
      expect(body).to include('DigitalOcean')
    end
  end

  describe 'GET /terms' do
    it 'returns 200 with the page header + key sections' do
      get '/terms'
      expect(last_response.status).to eq(200)
      body = last_response.body
      expect(body).to include('<h2>Terms of Use</h2>')
      expect(body).to include('What you can do')
      expect(body).to include('What you agree not to do')
      expect(body).to include('Availability + warranty')
      expect(body).to include('Termination')
      expect(body).to include('Governing law')
    end
  end

  describe 'footer links' do
    it 'links to /privacy + /terms from the layout footer' do
      get '/about'
      expect(last_response.body).to include('href="/privacy"')
      expect(last_response.body).to include('href="/terms"')
    end
  end
end
