require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/sports_leagues_store'
require_relative '../app/sports_teams_store'
require_relative '../app/sports_standings_store'
require_relative '../app/sports_follows_store'
require_relative '../app/providers/espn'

# Sports Phase S8 — league standings.
#
# Three layers covered:
#   1. SportsStandingsStore (idempotent upsert + lookups)
#   2. Providers::ESPN.standings (HTTP-stubbed JSON normalization)
#   3. /sports/league/:slug route + per-team standing subtitle

def make_league(slug:, sport: 'football', source: 'espn')
  SportsLeaguesStore.upsert(
    slug: slug, name: slug.upcase, sport: sport,
    source_provider: source, external_id: "#{sport}/#{slug}"
  )
end

def make_team(league:, slug:, name:, external_id:)
  SportsTeamsStore.upsert(
    league_id: league['id'], slug: slug, name: name, short_name: slug.capitalize,
    source_provider: 'espn', external_id: external_id, image_url: 'https://logo.example/team.png'
  )
end

RSpec.describe SportsStandingsStore do
  let(:league) { make_league(slug: 'nfl') }
  let(:team)   { make_team(league: league, slug: 'eagles', name: 'Eagles', external_id: '21') }

  describe '.upsert' do
    it 'inserts a new standings row' do
      row = SportsStandingsStore.upsert(
        league_id: league['id'], team_id: team['id'], group_name: 'NFC',
        source_provider: 'espn', position: 3, wins: 11, losses: 6, win_percent: '.647',
        point_differential: 54, streak: 'L1', playoff_seed: 3
      )
      expect(row['wins']).to eq(11)
      expect(row['streak']).to eq('L1')
      expect(row['last_synced_at']).not_to be_nil
    end

    it 'is idempotent on (source_provider, league_id, group_name, team_id)' do
      args = { league_id: league['id'], team_id: team['id'], group_name: 'NFC',
               source_provider: 'espn' }
      a = SportsStandingsStore.upsert(**args.merge(wins: 5, losses: 0))
      b = SportsStandingsStore.upsert(**args.merge(wins: 11, losses: 6))
      expect(b['id']).to eq(a['id'])
      expect(b['wins']).to eq(11)
      expect(SportsStandingsStore.count).to eq(1)
    end
  end

  describe '.for_league + .for_team' do
    let(:other) { make_team(league: league, slug: 'cowboys', name: 'Cowboys', external_id: '6') }

    before do
      SportsStandingsStore.upsert(league_id: league['id'], team_id: team['id'], group_name: 'NFC',
                                   source_provider: 'espn', position: 3, wins: 11, losses: 6)
      SportsStandingsStore.upsert(league_id: league['id'], team_id: other['id'], group_name: 'NFC',
                                   source_provider: 'espn', position: 7, wins: 7, losses: 10)
    end

    it 'for_league returns rows ordered by group + position' do
      rows = SportsStandingsStore.for_league(league['id'])
      expect(rows.length).to eq(2)
      expect(rows.map { |r| r['team_id'] }).to eq([team['id'], other['id']])  # position 3 before 7
    end

    it 'for_team returns the latest row for that team' do
      expect(SportsStandingsStore.for_team(team['id'])['position']).to eq(3)
    end

    it 'for_team returns nil for a team with no standings synced' do
      stranger = make_team(league: league, slug: 'giants', name: 'Giants', external_id: '19')
      expect(SportsStandingsStore.for_team(stranger['id'])).to be_nil
    end
  end
end

RSpec.describe Providers::ESPN, '.standings' do
  def stub(url, code: 200, body:)
    double('Response', code: code.to_s, body: body.is_a?(String) ? body : JSON.generate(body))
  end

  let(:body) do
    {
      'children' => [
        { 'name' => 'American Football Conference',
          'children' => [
            { 'name' => 'AFC',
              'standings' => { 'entries' => [
                { 'team' => { 'id' => '12', 'displayName' => 'Chiefs',
                              'logos' => [{ 'href' => 'https://logo/kc.png' }] },
                  'stats' => [
                    { 'name' => 'wins',           'displayValue' => '14', 'value' => 14 },
                    { 'name' => 'losses',         'displayValue' => '3',  'value' => 3 },
                    { 'name' => 'winPercent',     'displayValue' => '.824' },
                    { 'name' => 'pointDifferential', 'displayValue' => '+120', 'value' => 120 },
                    { 'name' => 'streak',         'displayValue' => 'W4' },
                    { 'name' => 'playoffSeed',    'displayValue' => '1', 'value' => 1 }
                  ] }
              ] } }
          ] },
        { 'name' => 'National Football Conference',
          'children' => [
            { 'name' => 'NFC',
              'standings' => { 'entries' => [
                { 'team' => { 'id' => '21', 'displayName' => 'Eagles' },
                  'stats' => [
                    { 'name' => 'wins',           'displayValue' => '11', 'value' => 11 },
                    { 'name' => 'losses',         'displayValue' => '6',  'value' => 6 },
                    { 'name' => 'streak',         'displayValue' => 'L1' },
                    { 'name' => 'playoffSeed',    'displayValue' => '3', 'value' => 3 }
                  ] }
              ] } }
          ] }
      ]
    }
  end

  it 'walks the nested tree and returns a StandingsGroup per leaf with entries' do
    s = ->(_url) { stub('x', body: body) }
    groups = Providers::ESPN.standings(sport_path: 'football/nfl', http_get: s)
    expect(groups.length).to eq(2)
    expect(groups.map(&:group_name)).to contain_exactly('AFC', 'NFC')
    nfc = groups.find { |g| g.group_name == 'NFC' }
    eagles = nfc.entries.first
    expect(eagles.team_external_id).to eq('21')
    expect(eagles.wins).to eq(11)
    expect(eagles.streak).to eq('L1')
    expect(eagles.playoff_seed).to eq(3)
  end

  it 'extracts logo from team.logos when present' do
    s = ->(_url) { stub('x', body: body) }
    groups = Providers::ESPN.standings(sport_path: 'football/nfl', http_get: s)
    afc = groups.find { |g| g.group_name == 'AFC' }
    expect(afc.entries.first.team_logo).to eq('https://logo/kc.png')
  end

  it 'returns [] on non-200 / parse error / network failure' do
    expect(Providers::ESPN.standings(sport_path: 'football/nfl',
                                       http_get: ->(_) { stub('x', code: 500, body: '') })).to eq([])
    expect(Providers::ESPN.standings(sport_path: 'football/nfl',
                                       http_get: ->(_) { stub('x', body: 'not json') })).to eq([])
    expect(Providers::ESPN.standings(sport_path: 'football/nfl',
                                       http_get: ->(_) { raise StandardError, 'x' })).to eq([])
  end
end

RSpec.describe '/sports/league/:slug' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'renders the league standings grouped by group_name' do
    league = make_league(slug: 'nfl')
    eagles = make_team(league: league, slug: 'eagles', name: 'Philadelphia Eagles', external_id: '21')
    cowboys = make_team(league: league, slug: 'cowboys', name: 'Dallas Cowboys', external_id: '6')

    SportsStandingsStore.upsert(league_id: league['id'], team_id: eagles['id'], group_name: 'NFC',
                                 source_provider: 'espn', position: 3, wins: 11, losses: 6,
                                 win_percent: '.647', point_differential: 54, streak: 'L1')
    SportsStandingsStore.upsert(league_id: league['id'], team_id: cowboys['id'], group_name: 'NFC',
                                 source_provider: 'espn', position: 7, wins: 7, losses: 10,
                                 win_percent: '.412', point_differential: -45, streak: 'W2')
    SportsFollowsStore.add(kind: 'team', value: 'eagles')

    get '/sports/league/nfl'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('NFL — Standings')
    expect(last_response.body).to include('Philadelphia Eagles')
    expect(last_response.body).to include('Dallas Cowboys')
    # Match Eagles row carries the followed class; Cowboys row does not.
    rows        = last_response.body.scan(%r{<tr\b[^>]*>[\s\S]*?</tr>})
    eagles_row  = rows.find { |r| r.include?('Philadelphia Eagles') }
    cowboys_row = rows.find { |r| r.include?('Dallas Cowboys') }
    expect(eagles_row).to     include('sports-standings-followed')
    expect(cowboys_row).not_to include('sports-standings-followed')
    # Eagles' positive diff prefixed with "+"; Cowboys' negative diff bare.
    expect(last_response.body).to include('+54')
    expect(last_response.body).to include('-45')
  end

  it '404s on unknown slug' do
    get '/sports/league/middle-of-nowhere'
    expect(last_response.status).to eq(404)
  end

  it 'renders an empty-state when no standings have been synced' do
    make_league(slug: 'nfl')
    get '/sports/league/nfl'
    expect(last_response.body).to include('No standings synced')
  end
end

RSpec.describe '/sports TOC By-league row (S8)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'omits the By-league row when no league has synced standings' do
    get '/sports'
    expect(last_response.body).not_to include('class="sports-toc-row sports-toc-leagues"')
  end

  it 'renders one By-league pill per league with synced standings — followed-team not required' do
    league = make_league(slug: 'nfl')
    eagles = make_team(league: league, slug: 'eagles', name: 'Philadelphia Eagles', external_id: '21')
    SportsStandingsStore.upsert(league_id: league['id'], team_id: eagles['id'],
                                 group_name: 'NFC', source_provider: 'espn',
                                 position: 3, wins: 11, losses: 6)
    # Note: NO sports_follows row — pill should still render so
    # globally-interesting tournaments (FIFA World Cup) surface
    # even when the user doesn't follow a specific team in them.

    get '/sports'
    expect(last_response.body).to include('class="sports-toc-row sports-toc-leagues"')
    expect(last_response.body).to include('href="/sports/league/nfl"')
    expect(last_response.body).to include('class="sports-toc-button sports-toc-league"')
  end

  it 'omits leagues without standings yet' do
    make_league(slug: 'nfl')
    get '/sports'
    expect(last_response.body).not_to include('class="sports-toc-row sports-toc-leagues"')
  end
end

RSpec.describe '/sports/team/:slug standing subtitle' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'shows the league-position subtitle when standings exist for the team' do
    league = make_league(slug: 'nfl')
    eagles = make_team(league: league, slug: 'eagles', name: 'Philadelphia Eagles', external_id: '21')
    SportsStandingsStore.upsert(league_id: league['id'], team_id: eagles['id'],
                                 group_name: 'National Football Conference',
                                 source_provider: 'espn', position: 3, wins: 11, losses: 6, streak: 'L1')

    # Subscribe to the corresponding feed so the team page renders.
    FeedsStore.add(url: 'https://www.bleedinggreennation.com/rss/index.xml', title: 'BGN', topic: 'sports')

    get '/sports/team/eagles'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('class="subtitle sports-team-standing"')
    expect(last_response.body).to include('National Football Conference')
    expect(last_response.body).to match(/3<sup>rd<\/sup>/)
    expect(last_response.body).to include('(11&ndash;6)')
    expect(last_response.body).to include('streak L1')
    expect(last_response.body).to include('href="/sports/league/nfl"')
  end

  it 'omits the standing subtitle when no standings synced' do
    make_league(slug: 'nfl')
    make_team(league: SportsLeaguesStore.find_by_slug('nfl'), slug: 'eagles',
              name: 'Eagles', external_id: '21')
    FeedsStore.add(url: 'https://www.bleedinggreennation.com/rss/index.xml', title: 'BGN', topic: 'sports')
    get '/sports/team/eagles'
    expect(last_response.body).not_to include('sports-team-standing')
  end
end

RSpec.describe 'position_suffix helper' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  # The helper is a method on the route handler, not directly
  # exposed. Verify behaviour through the rendered output for a
  # range of positions.
  [1, 2, 3, 4, 11, 12, 13, 21, 22, 101].each do |n|
    it "renders position #{n} with the right ordinal suffix" do
      league = make_league(slug: "test-#{n}")
      team   = make_team(league: league, slug: "team-#{n}", name: "T#{n}", external_id: n.to_s)
      SportsStandingsStore.upsert(league_id: league['id'], team_id: team['id'],
                                   group_name: 'G', source_provider: 'espn',
                                   position: n, wins: 1, losses: 0)
      # We can't render /sports/team for these arbitrary teams since
      # they don't have SportsTeams (Ruby module) entries. Test the
      # helper indirectly via the standings page where positions
      # are just numbers — easier: render directly into a tiny app
      # context. Skip to a unit-level expectation instead.
      app_instance = TechFeedReader.new!
      expected = case n
                 when 1 then 'st'
                 when 2 then 'nd'
                 when 3 then 'rd'
                 when 11, 12, 13 then 'th'
                 when 21 then 'st'
                 when 22 then 'nd'
                 when 101 then 'st'
                 else 'th'
                 end
      expect(app_instance.send(:position_suffix, n)).to eq(expected)
    end
  end
end
