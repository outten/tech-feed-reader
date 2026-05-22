require_relative 'spec_helper'
require_relative '../app/main'

# STUFF #54 — sports follow / unfollow routes now return JSON when the
# client sends Accept: application/json. The HTML form-submit path (no
# Accept header signalling JSON) still 302s, so non-JS users get the
# original behaviour. Spec locks the contract end-to-end for the four
# routes the AJAX handler in public/sports-follow.js depends on.
RSpec.describe 'sports follow JSON contract (STUFF #54)' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  describe 'POST /sports/players/follow' do
    let(:slug) { 'jannik-sinner' }
    before do
      allow(SportsPlayersStore).to receive(:find_by_slug).with(slug).and_return({ 'slug' => slug })
      allow(SportsFollowsStore).to receive(:add)
    end

    it 'returns {ok, slug, kind, followed:true} JSON when Accept: application/json' do
      post '/sports/players/follow', { slug: slug }, { 'HTTP_ACCEPT' => 'application/json' }
      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('application/json')
      body = JSON.parse(last_response.body)
      expect(body).to include('ok' => true, 'slug' => slug, 'kind' => 'player', 'followed' => true)
    end

    it 'still 302s on a regular form submit (no JSON accept)' do
      post '/sports/players/follow', { slug: slug, return_to: '/sports/tennis' }
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to end_with('/sports/tennis')
    end
  end

  describe 'POST /sports/players/unfollow' do
    let(:slug) { 'jannik-sinner' }
    before { allow(SportsFollowsStore).to receive(:remove) }

    it 'returns {followed:false} JSON on Accept: application/json' do
      post '/sports/players/unfollow', { slug: slug }, { 'HTTP_ACCEPT' => 'application/json' }
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body).to include('ok' => true, 'slug' => slug, 'kind' => 'player', 'followed' => false)
    end
  end

  describe 'POST /sports/teams/follow' do
    let(:slug) { 'philadelphia-eagles' }
    let(:team) { { 'id' => 99, 'slug' => slug, 'source_provider' => 'espn' } }
    before do
      allow(SportsTeamsStore).to receive(:find_by_slug).with(slug).and_return(team)
      allow(SportsFollowsStore).to receive(:add)
      allow(SportsTeamFetchWorker).to receive(:perform_async)
    end

    it 'returns {followed:true, kind:team} JSON on Accept: application/json' do
      post '/sports/teams/follow', { slug: slug }, { 'HTTP_ACCEPT' => 'application/json' }
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body).to include('ok' => true, 'slug' => slug, 'kind' => 'team', 'followed' => true)
    end
  end

  describe 'POST /sports/teams/unfollow' do
    let(:slug) { 'philadelphia-eagles' }
    before { allow(SportsFollowsStore).to receive(:remove) }

    it 'returns {followed:false} JSON on Accept: application/json' do
      post '/sports/teams/unfollow', { slug: slug }, { 'HTTP_ACCEPT' => 'application/json' }
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body).to include('ok' => true, 'slug' => slug, 'kind' => 'team', 'followed' => false)
    end
  end

  describe 'public/sports-follow.js (lockdown)' do
    let(:js) { File.read(File.expand_path('../public/sports-follow.js', __dir__)) }

    it 'POSTs with Accept: application/json so the routes route through the JSON branch' do
      expect(js).to include("'Accept': 'application/json'")
    end

    it 'guards against double-wiring across DOMContentLoaded + turbo:load' do
      expect(js).to include('sportsFollowBound')
    end

    it 'targets the .js-sports-follow-form class so old non-JS forms still fall back to 302' do
      expect(js).to include('.js-sports-follow-form')
    end
  end
end
