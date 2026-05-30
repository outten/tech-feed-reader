require_relative 'spec_helper'
require_relative '../app/sports_sync'
require_relative '../app/sports_leagues_store'
require_relative '../app/sports_teams_store'
require_relative '../app/sports_matches_store'
require_relative '../app/sports_follows_store'
require_relative '../app/providers/espn'

# STUFF #70 follow-up — sync_followed_league_events! pulls matches
# for every league the user follows directly (kind='league'). Before
# this, following the FIFA World Cup as a tournament left the
# matches table empty unless the user also followed specific
# participating teams; sync_team_schedules! only iterates kind='team'.

RSpec.describe SportsSync, '.sync_followed_league_events!' do
  let(:logger) { double('AppLogger', info: nil, warn: nil) }

  def make_espn_event(external_id:, scheduled_at:, status: 'scheduled',
                      home_id: 'h1', home_name: 'Brazil', home_logo: 'https://e.com/h.png',
                      away_id: 'a1', away_name: 'Argentina', away_logo: 'https://e.com/a.png',
                      home_score: nil, away_score: nil)
    Providers::ESPN::Match.new(
      external_id: external_id, scheduled_at: scheduled_at, status: status,
      home_team_external_id: home_id, home_team_name: home_name, home_team_logo: home_logo,
      away_team_external_id: away_id, away_team_name: away_name, away_team_logo: away_logo,
      home_score: home_score, away_score: away_score, period: nil, venue: 'Maracanã'
    )
  end

  it 'pulls events for ESPN-source leagues the user follows directly' do
    league = SportsLeaguesStore.upsert(slug: 'fifa-world', name: 'FIFA World Cup',
                                       sport: 'soccer', source_provider: 'espn',
                                       external_id: 'soccer/fifa.world')
    SportsFollowsStore.add(user_id: 1, kind: 'league', value: 'fifa-world')

    allow(Providers::ESPN).to receive(:league_scoreboard)
      .with(sport_path: 'soccer/fifa.world')
      .and_return([
        make_espn_event(external_id: 'evt-1', scheduled_at: '2026-06-12T20:00Z'),
        make_espn_event(external_id: 'evt-2', scheduled_at: '2026-06-13T17:00Z',
                        home_id: 'h2', home_name: 'Spain', away_id: 'a2', away_name: 'Germany')
      ])

    count = SportsSync.sync_followed_league_events!(logger: logger)
    expect(count).to eq(2)
    rows = Database.connection.execute('SELECT * FROM sports_matches WHERE league_id = ?', [league['id']])
    expect(rows.length).to eq(2)
  end

  it 'skips leagues without an ESPN source (catalog-only tournaments)' do
    SportsLeaguesStore.upsert(slug: 'roland-garros', name: 'Roland Garros',
                              sport: 'tennis', source_provider: 'catalog',
                              external_id: 'roland-garros')
    SportsFollowsStore.add(user_id: 1, kind: 'league', value: 'roland-garros')

    expect(Providers::ESPN).not_to receive(:league_scoreboard)
    expect(SportsSync.sync_followed_league_events!(logger: logger)).to eq(0)
  end

  it 'returns 0 cleanly when no leagues are followed' do
    expect(SportsSync.sync_followed_league_events!(logger: logger)).to eq(0)
  end

  it 'logs + continues past an ESPN error on one league' do
    SportsLeaguesStore.upsert(slug: 'fifa-world', name: 'FIFA World Cup',
                              sport: 'soccer', source_provider: 'espn',
                              external_id: 'soccer/fifa.world')
    SportsLeaguesStore.upsert(slug: 'uefa-euro', name: 'UEFA Euro',
                              sport: 'soccer', source_provider: 'espn',
                              external_id: 'soccer/uefa.euro')
    SportsFollowsStore.add(user_id: 1, kind: 'league', value: 'fifa-world')
    SportsFollowsStore.add(user_id: 1, kind: 'league', value: 'uefa-euro')

    allow(Providers::ESPN).to receive(:league_scoreboard)
      .with(sport_path: 'soccer/fifa.world').and_raise(StandardError, 'transport')
    allow(Providers::ESPN).to receive(:league_scoreboard)
      .with(sport_path: 'soccer/uefa.euro')
      .and_return([make_espn_event(external_id: 'euro-1', scheduled_at: '2026-06-14T18:00Z')])

    expect(logger).to receive(:warn).with('sports_sync_league_events_error',
                                          hash_including(slug: 'fifa-world'))
    expect(SportsSync.sync_followed_league_events!(logger: logger)).to eq(1) # only Euro succeeds
  end
end
