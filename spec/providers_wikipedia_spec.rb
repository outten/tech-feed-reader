require_relative 'spec_helper'
require_relative '../app/logger'
require_relative '../app/sports_leagues_store'
require_relative '../app/providers/wikipedia'

# STUFF #73 — Wikipedia REST API summary provider. Stubbed HTTP so
# the suite never hits Wikipedia live.

RSpec.describe Providers::Wikipedia, '.summary' do
  let(:payload) do
    {
      'title'        => 'FIFA World Cup',
      'extract'      => 'The FIFA World Cup, often called the World Cup, is an international association football competition.',
      'extract_html' => '<p>The <b>FIFA World Cup</b>…</p>',
      'thumbnail'    => { 'source' => 'https://upload.wikimedia.org/.../FIFA_World_Cup.png' },
      'content_urls' => { 'desktop' => { 'page' => 'https://en.wikipedia.org/wiki/FIFA_World_Cup' } }
    }
  end
  let(:ok_response) { instance_double(Net::HTTPSuccess, code: '200', body: payload.to_json) }

  it 'returns a populated Summary struct on 200' do
    s = Providers::Wikipedia.summary('FIFA World Cup', http_get: ->(_) { ok_response })
    expect(s.title).to eq('FIFA World Cup')
    expect(s.extract).to include('international association football')
    expect(s.thumbnail_url).to eq('https://upload.wikimedia.org/.../FIFA_World_Cup.png')
    expect(s.page_url).to eq('https://en.wikipedia.org/wiki/FIFA_World_Cup')
  end

  it 'returns nil on blank title' do
    expect(Providers::Wikipedia.summary('', http_get: ->(_) { ok_response })).to be_nil
    expect(Providers::Wikipedia.summary(nil, http_get: ->(_) { ok_response })).to be_nil
  end

  it 'returns nil on non-200 response' do
    not_found = instance_double(Net::HTTPNotFound, code: '404', body: 'missing')
    expect(Providers::Wikipedia.summary('Made-up Page', http_get: ->(_) { not_found })).to be_nil
  end

  it 'percent-encodes the title path segment + accepts underscores' do
    received_url = nil
    fake_get = lambda do |url|
      received_url = url
      ok_response
    end
    Providers::Wikipedia.summary('Roland_Garros', http_get: fake_get)
    expect(received_url).to include('/page/summary/')
    # Spaces stay encoded as %20 (CGI.escape), not '+'
    expect(received_url).to include('Roland%20Garros')
  end
end

RSpec.describe Providers::Wikipedia, '.refresh_for_league' do
  let(:payload) do
    {
      'title' => 'Tour de France', 'extract' => 'The Tour de France is an annual men\'s multiple stage bicycle race.',
      'extract_html' => '<p>The Tour de France is…</p>', 'thumbnail' => nil,
      'content_urls' => { 'desktop' => { 'page' => 'https://en.wikipedia.org/wiki/Tour_de_France' } }
    }
  end
  let(:ok_response) { instance_double(Net::HTTPSuccess, code: '200', body: payload.to_json) }

  it 'fetches + caches the summary on the league row when no cache exists' do
    league = SportsLeaguesStore.upsert(slug: 'tour-de-france', name: 'Tour de France',
                                       sport: 'cycling', source_provider: 'catalog',
                                       external_id: 'tour-de-france')
    SportsLeaguesStore.set_wikipedia_title!(league['id'], 'Tour de France')
    league = SportsLeaguesStore.find(league['id'])

    refreshed = Providers::Wikipedia.refresh_for_league(league, http_get: ->(_) { ok_response })
    expect(refreshed['wikipedia_summary']).not_to be_nil
    expect(JSON.parse(refreshed['wikipedia_summary'])['extract']).to include('annual men')
    expect(refreshed['wikipedia_summary_fetched_at']).not_to be_nil
  end

  it 'no-ops when wikipedia_title is empty (catalog never declared one)' do
    league = SportsLeaguesStore.upsert(slug: 'roland-garros', name: 'Roland Garros',
                                       sport: 'tennis', source_provider: 'catalog',
                                       external_id: 'roland-garros')
    fake_get = ->(_) { raise 'should not be called' }
    refreshed = Providers::Wikipedia.refresh_for_league(league, http_get: fake_get)
    expect(refreshed['wikipedia_summary']).to be_nil
  end

  it 'skips the fetch when the cache is fresh (within TTL)' do
    league = SportsLeaguesStore.upsert(slug: 'fifa-world', name: 'FIFA World Cup',
                                       sport: 'soccer', source_provider: 'espn',
                                       external_id: 'soccer/fifa.world')
    SportsLeaguesStore.set_wikipedia_title!(league['id'], 'FIFA World Cup')
    SportsLeaguesStore.set_wikipedia_summary!(league['id'], '{"extract":"cached"}', now: Time.now)
    league = SportsLeaguesStore.find(league['id'])

    fake_get = ->(_) { raise 'should not be called' }
    refreshed = Providers::Wikipedia.refresh_for_league(league, http_get: fake_get)
    expect(refreshed['wikipedia_summary']).to eq('{"extract":"cached"}')
  end

  it 'refetches when the cache is older than the TTL' do
    league = SportsLeaguesStore.upsert(slug: 'fifa-world', name: 'FIFA World Cup',
                                       sport: 'soccer', source_provider: 'espn',
                                       external_id: 'soccer/fifa.world')
    SportsLeaguesStore.set_wikipedia_title!(league['id'], 'FIFA World Cup')
    stale_time = Time.now - (25 * 60 * 60) # 25h ago > TTL
    SportsLeaguesStore.set_wikipedia_summary!(league['id'], '{"extract":"stale"}', now: stale_time)
    league = SportsLeaguesStore.find(league['id'])

    refreshed = Providers::Wikipedia.refresh_for_league(league, http_get: ->(_) { ok_response })
    expect(JSON.parse(refreshed['wikipedia_summary'])['extract']).to include('annual men')
  end
end
