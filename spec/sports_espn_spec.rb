require_relative 'spec_helper'
require_relative '../app/providers/espn'

# Sports Phase S4 — Providers::ESPN. Network is stubbed (the
# project's HTTP guard raises on any unstubbed Net::HTTP call in
# test env, so we provide a fake http_get instead). The interesting
# surface is JSON normalization: ESPN's competitor.score is
# sometimes a Hash {value, displayValue}, sometimes a flat string,
# sometimes nil. We need all three to land safely.

RSpec.describe Providers::ESPN do
  def make_response(code, body)
    double('Response', code: code.to_s, body: body.is_a?(String) ? body : JSON.generate(body))
  end

  describe '.normalize_event' do
    let(:event) do
      {
        'id' => 'evt-100',
        'date' => '2025-09-05T00:20Z',
        'status' => { 'type' => { 'name' => 'STATUS_FINAL', 'shortDetail' => 'Final' } },
        'competitions' => [{
          'venue' => { 'fullName' => 'Lincoln Financial Field' },
          'competitors' => [
            { 'homeAway' => 'home',
              'team' => { 'id' => '21', 'displayName' => 'Philadelphia Eagles' },
              'score' => { 'value' => 24.0, 'displayValue' => '24' } },
            { 'homeAway' => 'away',
              'team' => { 'id' => '6',  'displayName' => 'Dallas Cowboys' },
              'score' => { 'value' => 20.0, 'displayValue' => '20' } }
          ]
        }]
      }
    end

    it 'extracts identity, scores, status, and venue from a final event' do
      m = Providers::ESPN.normalize_event(event).first
      expect(m.external_id).to                eq('evt-100')
      expect(m.scheduled_at).to               eq('2025-09-05T00:20Z')
      expect(m.status).to                     eq('final')
      expect(m.home_team_external_id).to      eq('21')
      expect(m.home_team_name).to             eq('Philadelphia Eagles')
      expect(m.away_team_external_id).to      eq('6')
      expect(m.home_score).to                 eq(24)
      expect(m.away_score).to                 eq(20)
      expect(m.venue).to                      eq('Lincoln Financial Field')
    end

    it 'handles flat-string scores (some legacy ESPN endpoints)' do
      flat = JSON.parse(JSON.generate(event))
      flat['competitions'][0]['competitors'][0]['score'] = '24'
      flat['competitions'][0]['competitors'][1]['score'] = '20'
      m = Providers::ESPN.normalize_event(flat).first
      expect(m.home_score).to eq(24)
      expect(m.away_score).to eq(20)
    end

    it 'leaves scores as nil when the field is missing entirely' do
      no_score = JSON.parse(JSON.generate(event))
      no_score['competitions'][0]['competitors'][0].delete('score')
      no_score['competitions'][0]['competitors'][1].delete('score')
      m = Providers::ESPN.normalize_event(no_score).first
      expect(m.home_score).to be_nil
      expect(m.away_score).to be_nil
    end

    it 'maps STATUS_SCHEDULED → scheduled' do
      sched = JSON.parse(JSON.generate(event))
      sched['status']['type']['name'] = 'STATUS_SCHEDULED'
      expect(Providers::ESPN.normalize_event(sched).first.status).to eq('scheduled')
    end

    it 'maps STATUS_IN_PROGRESS → live' do
      live = JSON.parse(JSON.generate(event))
      live['status']['type']['name'] = 'STATUS_IN_PROGRESS'
      expect(Providers::ESPN.normalize_event(live).first.status).to eq('live')
    end

    it 'maps STATUS_POSTPONED → postponed' do
      pp = JSON.parse(JSON.generate(event))
      pp['status']['type']['name'] = 'STATUS_POSTPONED'
      expect(Providers::ESPN.normalize_event(pp).first.status).to eq('postponed')
    end

    it 'falls back to scheduled for unknown ESPN status codes' do
      unknown = JSON.parse(JSON.generate(event))
      unknown['status']['type']['name'] = 'STATUS_NEW_AND_UNDOCUMENTED'
      expect(Providers::ESPN.normalize_event(unknown).first.status).to eq('scheduled')
    end

    it 'returns [] for events with no competitions array' do
      expect(Providers::ESPN.normalize_event({ 'id' => 'x' })).to eq([])
    end

    it 'returns [] (rescued) for malformed events without raising' do
      expect(Providers::ESPN.normalize_event(nil)).to eq([])
    end
  end

  describe '.team_schedule' do
    let(:fake_body) do
      {
        'events' => [
          { 'id' => 'evt-1', 'date' => '2025-09-05T00:20Z',
            'status' => { 'type' => { 'name' => 'STATUS_FINAL' } },
            'competitions' => [{
              'competitors' => [
                { 'homeAway' => 'home', 'team' => { 'id' => '21', 'displayName' => 'Eagles' },
                  'score' => { 'displayValue' => '24' } },
                { 'homeAway' => 'away', 'team' => { 'id' => '6',  'displayName' => 'Cowboys' },
                  'score' => { 'displayValue' => '20' } }
              ]
            }] }
        ]
      }
    end

    it 'fetches the team schedule URL and returns normalized matches' do
      seen_url = nil
      stub = ->(url) { seen_url = url; make_response(200, fake_body) }
      result = Providers::ESPN.team_schedule(
        sport_path: 'football/nfl', team_external_id: '21', http_get: stub
      )
      expect(seen_url).to eq('https://site.api.espn.com/apis/site/v2/sports/football/nfl/teams/21/schedule')
      expect(result.length).to eq(1)
      expect(result.first.external_id).to eq('evt-1')
    end

    it 'returns [] (logged) on a non-200 response' do
      stub = ->(_url) { make_response(500, '') }
      expect(Providers::ESPN.team_schedule(sport_path: 'football/nfl', team_external_id: '21', http_get: stub)).to eq([])
    end

    it 'returns [] (logged) on malformed JSON' do
      stub = ->(_url) { make_response(200, 'not json') }
      expect(Providers::ESPN.team_schedule(sport_path: 'football/nfl', team_external_id: '21', http_get: stub)).to eq([])
    end

    it 'returns [] when the network raises' do
      stub = ->(_url) { raise StandardError, 'kaboom' }
      expect(Providers::ESPN.team_schedule(sport_path: 'football/nfl', team_external_id: '21', http_get: stub)).to eq([])
    end
  end

  describe '.league_scoreboard' do
    let(:fake_body) do
      {
        'events' => [
          { 'id' => 'evt-99', 'date' => '2027-10-01T10:45Z',
            'status' => { 'type' => { 'name' => 'STATUS_SCHEDULED' } },
            'competitions' => [{
              'competitors' => [
                { 'homeAway' => 'home', 'team' => { 'id' => '8',  'displayName' => 'New Zealand' } },
                { 'homeAway' => 'away', 'team' => { 'id' => '14', 'displayName' => 'Fiji' } }
              ]
            }] }
        ]
      }
    end

    it 'hits the scoreboard URL without dates by default' do
      seen_url = nil
      stub = ->(url) { seen_url = url; make_response(200, fake_body) }
      Providers::ESPN.league_scoreboard(sport_path: 'rugby/164205', http_get: stub)
      expect(seen_url).to eq('https://site.api.espn.com/apis/site/v2/sports/rugby/164205/scoreboard')
    end

    it 'appends ?dates= when dates is given' do
      seen_url = nil
      stub = ->(url) { seen_url = url; make_response(200, fake_body) }
      Providers::ESPN.league_scoreboard(sport_path: 'rugby/164205', dates: '20251101-20251130', http_get: stub)
      expect(seen_url).to end_with('?dates=20251101-20251130')
    end

    it 'returns the events from a 200 response' do
      stub = ->(_url) { make_response(200, fake_body) }
      result = Providers::ESPN.league_scoreboard(sport_path: 'rugby/164205', http_get: stub)
      expect(result.length).to eq(1)
      expect(result.first.home_team_name).to eq('New Zealand')
    end
  end

  describe 'STATUS_MAP coverage' do
    it 'covers the full ESPN status vocabulary the sync touches' do
      %w[STATUS_SCHEDULED STATUS_IN_PROGRESS STATUS_HALFTIME STATUS_FINAL
         STATUS_FULL_TIME STATUS_POSTPONED STATUS_CANCELED STATUS_FORFEIT].each do |code|
        expect(Providers::ESPN::STATUS_MAP[code]).not_to be_nil, "missing mapping for #{code}"
      end
    end
  end
end
