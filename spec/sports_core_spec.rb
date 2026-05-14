require_relative 'spec_helper'
require_relative '../app/sports_leagues_store'
require_relative '../app/sports_teams_store'
require_relative '../app/sports_matches_store'
require_relative '../app/sports_players_store'
require_relative '../app/sports_follows_store'

# Sports Phase S3 — schema + stores. Covers idempotent upsert
# semantics (the load-bearing property — sync runs hourly and
# must not duplicate rows), CRUD, and FK behaviour.

RSpec.describe SportsLeaguesStore do
  describe '.upsert' do
    it 'inserts a new league when none matches (slug, source, external_id)' do
      lg = SportsLeaguesStore.upsert(
        slug: 'nfl', name: 'NFL', sport: 'football',
        source_provider: 'espn', external_id: 'football/nfl'
      )
      expect(lg['id']).to be_a(Integer)
      expect(lg['slug']).to eq('nfl')
    end

    it 'is idempotent on (source_provider, external_id) — same id on re-upsert' do
      a = SportsLeaguesStore.upsert(slug: 'nfl', name: 'NFL', sport: 'football',
                                     source_provider: 'espn', external_id: 'football/nfl')
      b = SportsLeaguesStore.upsert(slug: 'nfl', name: 'NFL (renamed)', sport: 'football',
                                     source_provider: 'espn', external_id: 'football/nfl')
      expect(b['id']).to eq(a['id'])
      expect(b['name']).to eq('NFL (renamed)')
      expect(SportsLeaguesStore.count).to eq(1)
    end
  end

  describe 'lookups' do
    before do
      @lg = SportsLeaguesStore.upsert(
        slug: 'nba', name: 'NBA', sport: 'basketball',
        source_provider: 'espn', external_id: 'basketball/nba'
      )
    end

    it '.find_by_slug returns the league for a known slug' do
      expect(SportsLeaguesStore.find_by_slug('nba')['id']).to eq(@lg['id'])
    end

    it '.find_by_external matches on (source_provider, external_id)' do
      expect(SportsLeaguesStore.find_by_external('espn', 'basketball/nba')['id']).to eq(@lg['id'])
    end

    it 'returns nil for unknown slugs / external ids' do
      expect(SportsLeaguesStore.find_by_slug('cricket')).to be_nil
      expect(SportsLeaguesStore.find_by_external('espn', 'tennis/atp')).to be_nil
    end
  end
end

RSpec.describe SportsTeamsStore do
  let(:league) do
    SportsLeaguesStore.upsert(slug: 'nfl', name: 'NFL', sport: 'football',
                              source_provider: 'espn', external_id: 'football/nfl')
  end

  describe '.upsert' do
    it 'inserts a new team' do
      team = SportsTeamsStore.upsert(
        league_id: league['id'], slug: 'eagles',
        name: 'Philadelphia Eagles', short_name: 'Eagles',
        source_provider: 'espn', external_id: '21'
      )
      expect(team['short_name']).to eq('Eagles')
      expect(team['league_id']).to eq(league['id'])
    end

    it 'is idempotent on (source_provider, external_id)' do
      a = SportsTeamsStore.upsert(league_id: league['id'], slug: 'eagles',
                                   name: 'Eagles A', source_provider: 'espn', external_id: '21')
      b = SportsTeamsStore.upsert(league_id: league['id'], slug: 'eagles',
                                   name: 'Eagles B', source_provider: 'espn', external_id: '21')
      expect(b['id']).to eq(a['id'])
      expect(b['name']).to eq('Eagles B')
    end
  end

  describe '.for_league' do
    it 'returns only teams in the given league' do
      other = SportsLeaguesStore.upsert(slug: 'nba', name: 'NBA', sport: 'basketball',
                                         source_provider: 'espn', external_id: 'basketball/nba')
      SportsTeamsStore.upsert(league_id: league['id'], slug: 'eagles',
                               name: 'Eagles', source_provider: 'espn', external_id: '21')
      SportsTeamsStore.upsert(league_id: other['id'], slug: 'sixers',
                               name: 'Sixers', source_provider: 'espn', external_id: '20')
      expect(SportsTeamsStore.for_league(league['id']).map { |t| t['slug'] }).to eq(['eagles'])
    end
  end

  describe 'cascade delete' do
    it 'drops teams when their league is deleted' do
      SportsTeamsStore.upsert(league_id: league['id'], slug: 'eagles',
                               name: 'Eagles', source_provider: 'espn', external_id: '21')
      Database.connection.execute('DELETE FROM sports_leagues WHERE id = ?', [league['id']])
      expect(SportsTeamsStore.count).to eq(0)
    end
  end
end

RSpec.describe SportsMatchesStore do
  let(:league) do
    SportsLeaguesStore.upsert(slug: 'nfl', name: 'NFL', sport: 'football',
                              source_provider: 'espn', external_id: 'football/nfl')
  end
  let(:eagles) do
    SportsTeamsStore.upsert(league_id: league['id'], slug: 'eagles',
                             name: 'Eagles', source_provider: 'espn', external_id: '21')
  end
  let(:cowboys) do
    SportsTeamsStore.upsert(league_id: league['id'], slug: 'cowboys',
                             name: 'Cowboys', source_provider: 'espn', external_id: '6')
  end

  describe '.upsert' do
    it 'persists a match with both teams + scores' do
      m = SportsMatchesStore.upsert(
        league_id: league['id'], source_provider: 'espn', external_id: 'evt-1',
        scheduled_at: '2025-09-05T00:20Z', status: 'final',
        home_team_id: eagles['id'], away_team_id: cowboys['id'],
        home_score: 24, away_score: 20
      )
      expect(m['home_score']).to eq(24)
      expect(m['away_score']).to eq(20)
      expect(m['last_synced_at']).not_to be_nil
    end

    it 'is idempotent on (source_provider, external_id)' do
      args = { league_id: league['id'], source_provider: 'espn', external_id: 'evt-2',
               scheduled_at: '2025-09-05T00:20Z', status: 'scheduled' }
      a = SportsMatchesStore.upsert(**args)
      b = SportsMatchesStore.upsert(**args.merge(status: 'final', home_score: 24, away_score: 20))
      expect(b['id']).to eq(a['id'])
      expect(b['status']).to eq('final')
      expect(SportsMatchesStore.count).to eq(1)
    end

    it 'rejects an unknown status value' do
      expect {
        SportsMatchesStore.upsert(league_id: league['id'], source_provider: 'espn', external_id: 'x',
                                   scheduled_at: '2025-09-05T00:20Z', status: 'pending')
      }.to raise_error(ArgumentError, /unknown status/)
    end
  end

  describe '.recent_finals_for_team / .upcoming_for_team' do
    before do
      SportsMatchesStore.upsert(league_id: league['id'], source_provider: 'espn', external_id: 'past-1',
                                 scheduled_at: '2025-09-05T00:20Z', status: 'final',
                                 home_team_id: eagles['id'], away_team_id: cowboys['id'],
                                 home_score: 24, away_score: 20)
      SportsMatchesStore.upsert(league_id: league['id'], source_provider: 'espn', external_id: 'fut-1',
                                 scheduled_at: '2030-01-01T00:00Z', status: 'scheduled',
                                 home_team_id: eagles['id'], away_team_id: cowboys['id'])
    end

    it 'recent_finals returns only finals involving the team' do
      finals = SportsMatchesStore.recent_finals_for_team(eagles['id'])
      expect(finals.map { |m| m['external_id'] }).to eq(['past-1'])
    end

    it 'upcoming returns scheduled matches in the future for the team' do
      upcoming = SportsMatchesStore.upcoming_for_team(eagles['id'], now: Time.parse('2025-10-01T00:00Z').utc)
      expect(upcoming.map { |m| m['external_id'] }).to eq(['fut-1'])
    end
  end
end

RSpec.describe SportsFollowsStore do
  describe '.add' do
    it 'inserts a new follow row' do
      expect(SportsFollowsStore.add(user_id: 1, kind: 'team', value: 'eagles')).to be(true)
      expect(SportsFollowsStore.count(1)).to eq(1)
    end

    it 'is idempotent — re-adding returns false (no new row)' do
      SportsFollowsStore.add(user_id: 1, kind: 'team', value: 'eagles')
      expect(SportsFollowsStore.add(user_id: 1, kind: 'team', value: 'eagles')).to be(false)
      expect(SportsFollowsStore.count(1)).to eq(1)
    end

    it 'rejects unknown kind' do
      expect { SportsFollowsStore.add(user_id: 1, kind: 'made-up', value: 'x') }
        .to raise_error(ArgumentError, /unknown kind/)
    end

    it 'rejects empty value' do
      expect { SportsFollowsStore.add(user_id: 1, kind: 'team', value: '   ') }
        .to raise_error(ArgumentError, /value must be non-empty/)
    end

    it 'allows the same value across kinds' do
      SportsFollowsStore.add(user_id: 1, kind: 'team',   value: 'eagles')
      SportsFollowsStore.add(user_id: 1, kind: 'league', value: 'eagles')
      expect(SportsFollowsStore.count(1)).to eq(2)
    end
  end

  describe '.follow? + .for_kind + .remove' do
    it 'round-trips correctly' do
      SportsFollowsStore.add(user_id: 1, kind: 'team', value: 'eagles')
      SportsFollowsStore.add(user_id: 1, kind: 'team', value: 'sixers')
      expect(SportsFollowsStore.follow?(1, 'team', 'eagles')).to be(true)
      expect(SportsFollowsStore.follow?(1, 'team', 'lakers')).to be(false)
      expect(SportsFollowsStore.for_kind(1, 'team').map { |f| f['value'] }).to contain_exactly('eagles', 'sixers')
      expect(SportsFollowsStore.remove(user_id: 1, kind: 'team', value: 'eagles')).to eq(1)
      expect(SportsFollowsStore.follow?(1, 'team', 'eagles')).to be(false)
    end
  end
end
