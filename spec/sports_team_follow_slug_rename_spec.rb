require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/sports_teams_store'
require_relative '../app/sports_leagues_store'
require_relative '../app/sports_follows_store'

# STUFF #69 — fix the manage→follow path that left
# `sports_follows.value` and `sports_teams.slug` mismatched.
#
# Before this fix: ESPN standings sync created `nba-team-13` for the
# Lakers; user clicked + Follow on /sports/manage/basketball/nba; the
# POST stored value='lakers' in sports_follows but the DB row still
# had slug='nba-team-13'. /sports's `find_by_slug('lakers')` returned
# nil and the Lakers never showed up.
#
# After: ensure_catalog_team_in_db detects the slug mismatch and
# renames the DB row to the catalog slug before the upsert.

RSpec.describe SportsTeamsStore, '.rename_slug! (STUFF #69)' do
  it 'updates the slug column in place and returns the refreshed row' do
    league = SportsLeaguesStore.upsert(slug: 'nba', name: 'NBA', sport: 'basketball',
                                       source_provider: 'espn', external_id: 'basketball/nba')
    team   = SportsTeamsStore.upsert(league_id: league['id'], slug: 'nba-team-13',
                                     name: 'Los Angeles Lakers', source_provider: 'espn',
                                     external_id: '13')
    renamed = SportsTeamsStore.rename_slug!(team['id'], 'lakers')
    expect(renamed['slug']).to eq('lakers')
    expect(SportsTeamsStore.find_by_slug('lakers')).not_to be_nil
    expect(SportsTeamsStore.find_by_slug('nba-team-13')).to be_nil
  end

  it 'returns nil when new_slug is blank' do
    league = SportsLeaguesStore.upsert(slug: 'nba', name: 'NBA', sport: 'basketball',
                                       source_provider: 'espn', external_id: 'basketball/nba')
    team   = SportsTeamsStore.upsert(league_id: league['id'], slug: 'nba-team-13',
                                     name: 'Los Angeles Lakers', source_provider: 'espn',
                                     external_id: '13')
    expect(SportsTeamsStore.rename_slug!(team['id'], '')).to be_nil
    expect(SportsTeamsStore.find_by_slug('nba-team-13')).not_to be_nil
  end
end

# Driving the route directly: simulate the standings sync having
# created an auto-slug row, then POST /sports/teams/follow with the
# catalog slug and assert the DB row's slug is renamed.
RSpec.describe 'POST /sports/teams/follow — catalog slug rename (STUFF #69)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'renames an existing auto-slug DB row to the catalog slug, so /sports finds it' do
    # Pre-state: standings sync materialized the Lakers under
    # `nba-team-13`. No catalog row yet.
    league = SportsLeaguesStore.upsert(slug: 'nba', name: 'NBA', sport: 'basketball',
                                       source_provider: 'espn', external_id: 'basketball/nba')
    SportsTeamsStore.upsert(league_id: league['id'], slug: 'nba-team-13',
                            name: 'Los Angeles Lakers', source_provider: 'espn',
                            external_id: '13')

    expect(SportsTeamsStore.find_by_slug('lakers')).to be_nil      # canary

    # Manage page POSTs the catalog slug.
    post '/sports/teams/follow', slug: 'lakers', return_to: '/sports/manage/basketball/nba'

    # Row has been renamed.
    after = SportsTeamsStore.find_by_slug('lakers')
    expect(after).not_to be_nil
    expect(after['external_id']).to eq('13')
    expect(SportsTeamsStore.find_by_slug('nba-team-13')).to be_nil  # auto-slug gone
    # Follow uses the catalog slug now — so /sports's lookup hits.
    follows = SportsFollowsStore.for_kind(1, 'team').map { |f| f['value'] }
    expect(follows).to include('lakers')
  end

  it 'is a no-op when the row already has the catalog slug' do
    league = SportsLeaguesStore.upsert(slug: 'nba', name: 'NBA', sport: 'basketball',
                                       source_provider: 'espn', external_id: 'basketball/nba')
    SportsTeamsStore.upsert(league_id: league['id'], slug: 'lakers',
                            name: 'Los Angeles Lakers', source_provider: 'espn',
                            external_id: '13')

    expect { post '/sports/teams/follow', slug: 'lakers' }.not_to raise_error
    expect(SportsTeamsStore.find_by_slug('lakers')).not_to be_nil
    expect(SportsTeamsStore.for_league(league['id']).length).to eq(1)  # no duplicates
  end

  it 'still works for a brand-new follow with no pre-existing DB row' do
    # Catalog has 'lakers' with external_id '13', but the DB has
    # NEITHER an auto-slug row nor a catalog row yet (the standings
    # sync hasn't fired for NBA). Cold-start path through
    # ensure_catalog_team_in_db.
    post '/sports/teams/follow', slug: 'lakers'
    after = SportsTeamsStore.find_by_slug('lakers')
    expect(after).not_to be_nil
    expect(after['name']).to eq('Los Angeles Lakers')
  end
end
