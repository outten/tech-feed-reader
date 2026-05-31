require_relative 'spec_helper'
require_relative '../app/logger'
require_relative '../app/providers/jolpica_f1'

# STUFF #73 — Jolpica F1 (Ergast successor) provider. Smoke-tested
# live to confirm the endpoint shape; this spec stubs HTTP so the
# suite stays offline.

RSpec.describe Providers::JolpicaF1, '.season' do
  let(:successful_payload) do
    {
      'MRData' => {
        'RaceTable' => {
          'Races' => [
            { 'season' => '2026', 'round' => '1', 'raceName' => 'Bahrain Grand Prix',
              'date' => '2026-03-08',
              'Circuit' => { 'circuitName' => 'Bahrain International Circuit',
                             'Location' => { 'country' => 'Bahrain' } } },
            { 'season' => '2026', 'round' => '2', 'raceName' => 'Saudi Arabian Grand Prix',
              'date' => '2026-03-15',
              'Circuit' => { 'circuitName' => 'Jeddah Corniche Circuit',
                             'Location' => { 'country' => 'Saudi Arabia' } } }
          ]
        }
      }
    }
  end

  let(:ok_response) do
    instance_double(Net::HTTPSuccess, code: '200', body: successful_payload.to_json)
  end

  it 'returns one Race struct per round on a 200 response' do
    fake_get = ->(_url) { ok_response }
    races = Providers::JolpicaF1.season(2026, http_get: fake_get)
    expect(races.length).to eq(2)
    expect(races.first.race_name).to eq('Bahrain Grand Prix')
    expect(races.first.circuit_name).to eq('Bahrain International Circuit')
    expect(races.first.country).to eq('Bahrain')
    expect(races.first.round).to eq(1)
  end

  it 'marks past races as :final and future races as :scheduled' do
    payload = {
      'MRData' => {
        'RaceTable' => {
          'Races' => [
            { 'season' => '2020', 'round' => '1', 'raceName' => 'Past GP', 'date' => '2020-03-08',
              'Circuit' => { 'circuitName' => 'X', 'Location' => { 'country' => 'X' } } },
            { 'season' => '2099', 'round' => '2', 'raceName' => 'Future GP', 'date' => '2099-03-15',
              'Circuit' => { 'circuitName' => 'Y', 'Location' => { 'country' => 'Y' } } }
          ]
        }
      }
    }
    fake_get = ->(_url) { instance_double(Net::HTTPSuccess, code: '200', body: payload.to_json) }
    races = Providers::JolpicaF1.season(2099, http_get: fake_get)
    expect(races.find { |r| r.race_name == 'Past GP' }.status).to eq('final')
    expect(races.find { |r| r.race_name == 'Future GP' }.status).to eq('scheduled')
  end

  it 'returns [] on non-200 HTTP response' do
    fake_get = ->(_url) { instance_double(Net::HTTPNotFound, code: '404', body: '') }
    expect(Providers::JolpicaF1.season(2026, http_get: fake_get)).to eq([])
  end

  it 'returns [] on parse error without raising' do
    fake_get = ->(_url) { instance_double(Net::HTTPSuccess, code: '200', body: 'not-json') }
    expect(Providers::JolpicaF1.season(2026, http_get: fake_get)).to eq([])
  end
end

RSpec.describe Providers::JolpicaF1, '.season_results' do
  it 'flags races as :final and captures the podium winner' do
    payload = {
      'MRData' => {
        'RaceTable' => {
          'Races' => [
            { 'season' => '2026', 'round' => '1', 'raceName' => 'Bahrain Grand Prix',
              'date' => '2026-03-08',
              'Circuit' => { 'circuitName' => 'BIC', 'Location' => { 'country' => 'Bahrain' } },
              'Results' => [
                { 'position' => '1', 'Driver' => { 'givenName' => 'Max', 'familyName' => 'Verstappen' } },
                { 'position' => '2', 'Driver' => { 'givenName' => 'Lewis', 'familyName' => 'Hamilton' } }
              ] }
          ]
        }
      }
    }
    fake_get = ->(_url) { instance_double(Net::HTTPSuccess, code: '200', body: payload.to_json) }
    races = Providers::JolpicaF1.season_results(2026, http_get: fake_get)
    expect(races.first.status).to eq('final')
    expect(races.first.winner_full_name).to eq('Max Verstappen')
  end
end
