require_relative 'spec_helper'
require_relative '../app/main'

# STUFF.md #39 — Header navigation is gated behind signed_in?
# Anonymous visitors see logo + Sign in / Sign up + theme toggle only.
# Signed-in users see the full nav (Articles / Podcasts / Sports / …)
# and the Bus icon. (The Refresh-all button was removed once the
# hourly RefreshAllFeedsWorker cron took over its job.)
#
# Public paths (`/`, `/about`, `/sign-in`, `/sign-up`) are the only
# routes an anonymous visitor can actually reach — those are where
# the simpler header surfaces. Everything else 302's to /sign-in
# before the layout ever renders.
RSpec.describe 'Header (STUFF #39)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  describe 'anonymous (logged out)' do
    before do
      # spec_helper auto-signs-in user 1 when the auth wall is off
      # (the test default). Disable the auto-sign-in for this group
      # so we exercise the genuine logged-out path.
      allow_any_instance_of(TechFeedReader).to receive(:signed_in?).and_return(false)
      allow_any_instance_of(TechFeedReader).to receive(:current_user).and_return(nil)
      allow_any_instance_of(TechFeedReader).to receive(:current_user_id).and_return(nil)
    end

    %w[/ /about].each do |path|
      context "on #{path}" do
        it 'does NOT render the main nav' do
          get path
          expect(last_response.status).to eq(200)
          # Match the layout's <nav>…</nav> block specifically — the
          # nav-dropdown <div>s inside also have class="nav-…", so we
          # have to anchor on the actual tag.
          expect(last_response.body).not_to match(%r{<nav>}m)
        end

        it 'does NOT render the Bus icon' do
          get path
          expect(last_response.body).not_to include('aria-label="Bus mode"')
        end

        it 'renders the Sign in + Sign up links' do
          get path
          expect(last_response.body).to include('href="/sign-in"')
          expect(last_response.body).to include('href="/sign-up"')
        end

        it 'keeps the logo + theme toggle visible' do
          get path
          expect(last_response.body).to match(%r{<a class="logo"})
          expect(last_response.body).to include('id="theme-toggle"')
        end
      end
    end
  end

  describe 'signed-in' do
    it 'renders the full nav on /articles' do
      get '/articles'
      expect(last_response.body).to match(%r{<nav>}m)
      expect(last_response.body).to include('href="/articles"')
      expect(last_response.body).to include('href="/podcasts"')
      expect(last_response.body).to include('href="/sports"')
    end

    it 'renders the Bus icon on /articles' do
      get '/articles'
      expect(last_response.body).to include('aria-label="Bus mode"')
    end

    it 'renders the auth-chip (signed-in identifier) and not the sign-in/sign-up links' do
      get '/articles'
      expect(last_response.body).to include('auth-chip')
      # auth-chip ousts the sign-in / sign-up links per the elsif branch.
      expect(last_response.body).not_to match(%r{<a [^>]*href="/sign-up"})
    end
  end
end
