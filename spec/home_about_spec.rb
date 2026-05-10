require_relative 'spec_helper'
require_relative '../app/main'

# STUFF.md #13 — public home + about pages. / always renders the
# marketing home (no cookie redirect — newbies always land on the
# vision page; existing users use the nav Dashboard link).
RSpec.describe 'GET /' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'renders the marketing home + a CTA to /dashboard' do
    get '/'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Stop swivel-chairing')
    expect(last_response.body).to include('href="/dashboard"')
  end

  it 'does not set a tfr_seen cookie (cookie-redirect was removed)' do
    get '/'
    expect(last_response.headers['Set-Cookie'].to_s).not_to include('tfr_seen')
  end

  it 'home renders all six feature sections + the screenshots' do
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
