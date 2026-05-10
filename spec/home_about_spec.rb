require_relative 'spec_helper'
require_relative '../app/main'

# STUFF.md #13 — public home + about pages.
# Cookie-aware redirect: first visit to / shows the marketing home
# and sets a tfr_seen cookie; subsequent visits redirect to /dashboard
# so the existing single-user owner doesn't lose their muscle memory.
RSpec.describe 'GET / (cookie-aware home)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'first visit (no tfr_seen cookie) renders the marketing home + sets the cookie' do
    clear_cookies
    get '/'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Stop swivel-chairing')
    expect(last_response.body).to include('href="/dashboard"')
    expect(last_response.headers['Set-Cookie'].to_s).to include('tfr_seen=1')
  end

  it 'subsequent visit (tfr_seen=1) redirects to /dashboard' do
    set_cookie 'tfr_seen=1'
    get '/'
    expect(last_response.status).to eq(302)
    expect(last_response.headers['Location']).to end_with('/dashboard')
  end

  it 'home renders all six feature sections + the screenshots' do
    clear_cookies
    get '/'
    %w[
      One\ inbox\ for\ everything
      Ranked\ for\ you
      AI-assisted\ triage
      Summaries\ you\ can\ skim
      Podcasts\ that\ follow\ you
      Sports
    ].each do |fragment|
      expect(last_response.body).to include(fragment)
    end
    %w[dashboard for-you triage digest podcasts sports].each do |slug|
      expect(last_response.body).to include("/img/home/#{slug}.png")
    end
  end
end

RSpec.describe 'GET /about' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'renders the about page with the philosophy + tech sections' do
    get '/about'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('About Tech Feed Reader')
    expect(last_response.body).to include('Why this exists')
    expect(last_response.body).to include('How it works')
    expect(last_response.body).to include('Tech stack')
  end

  it 'links from the global footer on every page' do
    get '/dashboard'
    expect(last_response.body).to match(%r{<a href="/about"})
  end
end
