require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/sports_sync'
require_relative '../app/sports_teams_store'
require_relative '../app/sports_leagues_store'

# STUFF #68 — ensure_team! used to always create a fresh
# `<league>-team-<external_id>` row when its find_by_external missed.
# That meant every league not in seed_sports_data.rb's CATALOG_LEAGUES
# (e.g. MLB) ended up with duplicate rows: the manually-seeded catalog
# row + an auto-slug ESPN row. Now ensure_team! looks for a name-
# matching row in the league first and promotes it to ESPN-tracked.

RSpec.describe SportsSync, '.ensure_team! catalog promotion (STUFF #68)' do
  def seed_mlb_league
    SportsLeaguesStore.upsert(slug: 'mlb', name: 'MLB', sport: 'baseball',
                              source_provider: 'espn', external_id: 'baseball/mlb')
  end

  it 'promotes a pre-existing catalog row when the ESPN payload matches by name' do
    league = seed_mlb_league
    # Catalog row exists with manually-seeded slug + source='catalog'.
    SportsTeamsStore.upsert(league_id: league['id'], slug: 'phillies',
                            name: 'Philadelphia Phillies',
                            source_provider: 'catalog', external_id: 'phillies')

    # First sync arrives with ESPN external_id '22'.
    promoted = SportsSync.ensure_team!('22', 'Philadelphia Phillies',
                                        'https://logo.example/phillies.png', league: league)

    expect(promoted['slug']).to eq('phillies')                  # natural slug preserved
    expect(promoted['source_provider']).to eq('espn')           # promoted to ESPN-tracked
    expect(promoted['external_id']).to eq('22')                 # ESPN id wired in
    expect(promoted['image_url']).to eq('https://logo.example/phillies.png')

    # No duplicate row created.
    rows = SportsTeamsStore.for_league(league['id']).select { |r| r['name'] == 'Philadelphia Phillies' }
    expect(rows.length).to eq(1)
  end

  it 'falls back to auto-slug creation when no catalog row matches' do
    league = seed_mlb_league
    created = SportsSync.ensure_team!('77', 'Boise Hawks',
                                       'https://logo.example/hawks.png', league: league)
    expect(created['slug']).to eq('mlb-team-77')
    expect(created['source_provider']).to eq('espn')
    expect(created['external_id']).to eq('77')
  end

  it 'is idempotent on re-sync — a second call returns the same row' do
    league = seed_mlb_league
    SportsTeamsStore.upsert(league_id: league['id'], slug: 'phillies',
                            name: 'Philadelphia Phillies',
                            source_provider: 'catalog', external_id: 'phillies')

    first  = SportsSync.ensure_team!('22', 'Philadelphia Phillies',
                                      'https://logo.example/phillies.png', league: league)
    second = SportsSync.ensure_team!('22', 'Philadelphia Phillies',
                                      'https://logo.example/phillies.png', league: league)
    expect(second['id']).to eq(first['id'])
    expect(SportsTeamsStore.for_league(league['id']).length).to eq(1)
  end

  it 'is case-insensitive on name match' do
    league = seed_mlb_league
    SportsTeamsStore.upsert(league_id: league['id'], slug: 'dodgers',
                            name: 'Los Angeles Dodgers',  # mixed case in DB
                            source_provider: 'catalog', external_id: 'dodgers')

    # ESPN payload could come in slightly different case.
    promoted = SportsSync.ensure_team!('19', 'LOS ANGELES DODGERS', 'logo', league: league)
    expect(promoted['slug']).to eq('dodgers')
    expect(promoted['external_id']).to eq('19')
  end
end

RSpec.describe SportsTeamsStore, '.find_by_name_in_league (STUFF #68)' do
  it 'returns the row when name matches case-insensitively within the league' do
    league = SportsLeaguesStore.upsert(slug: 'mlb', name: 'MLB', sport: 'baseball',
                                       source_provider: 'espn', external_id: 'baseball/mlb')
    SportsTeamsStore.upsert(league_id: league['id'], slug: 'phillies',
                            name: 'Philadelphia Phillies',
                            source_provider: 'catalog', external_id: 'phillies')

    row = SportsTeamsStore.find_by_name_in_league('philadelphia phillies', league_id: league['id'])
    expect(row).not_to be_nil
    expect(row['slug']).to eq('phillies')
  end

  it 'returns nil when no name match in the league' do
    league = SportsLeaguesStore.upsert(slug: 'mlb', name: 'MLB', sport: 'baseball',
                                       source_provider: 'espn', external_id: 'baseball/mlb')
    expect(SportsTeamsStore.find_by_name_in_league('Atlanta Braves', league_id: league['id'])).to be_nil
  end

  it 'returns nil when name is blank or nil' do
    league = SportsLeaguesStore.upsert(slug: 'mlb', name: 'MLB', sport: 'baseball',
                                       source_provider: 'espn', external_id: 'baseball/mlb')
    expect(SportsTeamsStore.find_by_name_in_league('', league_id: league['id'])).to be_nil
    expect(SportsTeamsStore.find_by_name_in_league(nil, league_id: league['id'])).to be_nil
  end
end
