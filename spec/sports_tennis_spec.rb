require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/sports_players_store'
require_relative '../app/providers/espn'

# Sports Phase S7 — tennis rankings.
#
# Five surfaces:
#   1. SportsPlayersStore upsert (extended) + .top_ranked
#   2. Providers::ESPN.tennis_rankings (HTTP-stubbed)
#   3. /sports/tennis landing
#   4. /sports/player/:slug detail
#   5. /sports header "Tennis rankings →" link

def make_player(slug:, full_name:, tour: 'atp', current_rank: 1, **extra)
  SportsPlayersStore.upsert(
    sport:           'tennis',
    slug:            slug,
    full_name:       full_name,
    source_provider: 'espn',
    external_id:     extra[:external_id] || slug.tr('-', ''),
    country:         extra[:country],
    tour:            tour,
    current_rank:    current_rank,
    previous_rank:   extra[:previous_rank],
    points:          extra[:points],
    trend:           extra[:trend],
    headshot_url:    extra[:headshot_url],
    flag_url:        extra[:flag_url]
  )
end

RSpec.describe SportsPlayersStore, 'tennis extensions (Phase S7)' do
  describe '.upsert' do
    it 'persists the new tennis fields on insert' do
      p = make_player(slug: 'jannik-sinner', full_name: 'Jannik Sinner',
                      tour: 'atp', current_rank: 1, previous_rank: 1,
                      points: 14350.0, trend: '-',
                      headshot_url: 'https://h/sinner.png',
                      flag_url: 'https://h/ita.png',
                      country: 'ITA')
      expect(p['tour']).to eq('atp')
      expect(p['current_rank']).to eq(1)
      expect(p['points']).to eq(14350.0)
      expect(p['trend']).to eq('-')
      expect(p['headshot_url']).to eq('https://h/sinner.png')
      expect(p['last_synced_at']).not_to be_nil
    end

    it 'is idempotent on (source_provider, external_id) — updates rank/points' do
      a = make_player(slug: 'jannik-sinner', full_name: 'Jannik Sinner',
                      external_id: '3623', current_rank: 2, points: 12000.0)
      b = SportsPlayersStore.upsert(
        sport: 'tennis', slug: 'jannik-sinner', full_name: 'Jannik Sinner',
        source_provider: 'espn', external_id: '3623',
        tour: 'atp', current_rank: 1, points: 14350.0
      )
      expect(b['id']).to eq(a['id'])
      expect(b['current_rank']).to eq(1)
      expect(b['points']).to eq(14350.0)
      expect(SportsPlayersStore.count).to eq(1)
    end
  end

  describe '.top_ranked' do
    before do
      make_player(slug: 'sinner',  full_name: 'Sinner',  tour: 'atp', current_rank: 1)
      make_player(slug: 'alcaraz', full_name: 'Alcaraz', tour: 'atp', current_rank: 2)
      make_player(slug: 'sabalenka', full_name: 'Sabalenka', tour: 'wta', current_rank: 1)
      # Player without a current_rank — must be excluded.
      make_player(slug: 'unranked', full_name: 'Unranked', tour: 'atp', current_rank: nil)
    end

    it 'returns top ATP players ordered by current_rank' do
      rows = SportsPlayersStore.top_ranked(tour: 'atp')
      expect(rows.map { |r| r['slug'] }).to eq(%w[sinner alcaraz])
    end

    it 'scopes by tour' do
      expect(SportsPlayersStore.top_ranked(tour: 'wta').map { |r| r['slug'] }).to eq(['sabalenka'])
    end

    it 'honours limit' do
      expect(SportsPlayersStore.top_ranked(tour: 'atp', limit: 1).length).to eq(1)
    end

    it 'excludes players with NULL current_rank' do
      expect(SportsPlayersStore.top_ranked(tour: 'atp').map { |r| r['slug'] }).not_to include('unranked')
    end
  end
end

RSpec.describe Providers::ESPN, '.tennis_rankings' do
  def stub(body, code: 200)
    double('Response', code: code.to_s, body: body.is_a?(String) ? body : JSON.generate(body))
  end

  let(:body) do
    {
      'rankings' => [
        { 'name' => 'ATP', 'type' => 'atp',
          'ranks' => [
            { 'current' => 1, 'previous' => 1, 'points' => 14350.0, 'trend' => '-',
              'athlete' => {
                'id' => '3623', 'displayName' => 'Jannik Sinner',
                'firstName' => 'Jannik', 'lastName' => 'Sinner',
                'citizenshipCountry' => 'ITA',
                'flag' => { 'href' => 'https://h/ita.png' },
                'headshot' => { 'href' => 'https://h/sinner.png' },
                'age' => 23
              } },
            { 'current' => 2, 'previous' => 3, 'points' => 12960.0, 'trend' => '+1',
              'athlete' => {
                'id' => '4926', 'displayName' => 'Carlos Alcaraz',
                'citizenshipCountry' => 'ESP'
              } }
          ] }
      ]
    }
  end

  it 'returns one entry per ranked athlete with rank/points/trend' do
    s = ->(_url) { stub(body) }
    rows = Providers::ESPN.tennis_rankings(tour: 'atp', http_get: s)
    expect(rows.length).to eq(2)
    sinner = rows.first
    expect(sinner.tour).to eq('atp')
    expect(sinner.current_rank).to eq(1)
    expect(sinner.full_name).to eq('Jannik Sinner')
    expect(sinner.country).to eq('ITA')
    expect(sinner.headshot_url).to eq('https://h/sinner.png')
    expect(sinner.flag_url).to eq('https://h/ita.png')
  end

  it 'handles flat-string flag/headshot fields' do
    flat = JSON.parse(JSON.generate(body))
    flat['rankings'][0]['ranks'][0]['athlete']['flag']     = 'https://flat-flag.png'
    flat['rankings'][0]['ranks'][0]['athlete']['headshot'] = 'https://flat-head.png'
    s = ->(_url) { stub(flat) }
    rows = Providers::ESPN.tennis_rankings(tour: 'atp', http_get: s)
    expect(rows.first.flag_url).to     eq('https://flat-flag.png')
    expect(rows.first.headshot_url).to eq('https://flat-head.png')
  end

  it 'rejects unknown tour values' do
    expect {
      Providers::ESPN.tennis_rankings(tour: 'utr', http_get: ->(_) { stub({}) })
    }.to raise_error(ArgumentError, /atp.*wta/)
  end

  it 'returns [] on non-200 / parse error / network failure' do
    expect(Providers::ESPN.tennis_rankings(tour: 'atp', http_get: ->(_) { stub('', code: 500) })).to eq([])
    expect(Providers::ESPN.tennis_rankings(tour: 'atp', http_get: ->(_) { stub('not json') })).to eq([])
    expect(Providers::ESPN.tennis_rankings(tour: 'atp', http_get: ->(_) { raise StandardError, 'x' })).to eq([])
  end
end

RSpec.describe '/sports/tennis' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'renders the empty state when no rankings synced' do
    # STUFF #46 added on-page-load autosync — bypass via ?skip_refresh=1
    # so this spec stays focused on the empty-state copy, not on
    # whether ESPN happens to be reachable from the test runner.
    get '/sports/tennis?skip_refresh=1'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('No tennis rankings yet')
  end

  it 'renders ATP + WTA top tables when rankings exist' do
    make_player(slug: 'sinner',    full_name: 'Jannik Sinner',   tour: 'atp', current_rank: 1, country: 'ITA')
    make_player(slug: 'sabalenka', full_name: 'Aryna Sabalenka', tour: 'wta', current_rank: 1, country: 'BLR')
    get '/sports/tennis'
    # ERB doesn't auto-escape <%= label %> + the literal &mdash; so
    # the rendered HTML is "ATP &mdash; men's tour" (raw apostrophe).
    expect(last_response.body).to include("ATP &mdash; men's tour")
    expect(last_response.body).to include("WTA &mdash; women's tour")
    expect(last_response.body).to include('Jannik Sinner')
    expect(last_response.body).to include('Aryna Sabalenka')
  end

  it 'links each player row to /sports/player/:slug' do
    make_player(slug: 'sinner', full_name: 'Jannik Sinner', tour: 'atp', current_rank: 1)
    get '/sports/tennis'
    expect(last_response.body).to include('href="/sports/player/sinner"')
  end

  it 'shows trend arrows based on previous - current rank' do
    make_player(slug: 'rising',   full_name: 'Rising',   tour: 'atp', current_rank: 5,  previous_rank: 8)
    make_player(slug: 'falling',  full_name: 'Falling',  tour: 'atp', current_rank: 10, previous_rank: 6)
    make_player(slug: 'flat',     full_name: 'Flat',     tour: 'atp', current_rank: 12, previous_rank: 12)
    get '/sports/tennis'
    body = last_response.body
    expect(body).to match(/Rising[\s\S]*?&uarr; 3/)
    expect(body).to match(/Falling[\s\S]*?&darr; 4/)
    # No arrow for flat — pull just the Flat row by scanning all
    # <tr>...</tr> blocks and picking the one containing "Flat".
    rows     = body.scan(%r{<tr\b[^>]*>[\s\S]*?</tr>})
    flat_row = rows.find { |r| r.include?('Flat') }
    expect(flat_row).not_to be_nil
    expect(flat_row).not_to include('&uarr;')
    expect(flat_row).not_to include('&darr;')
  end

  it 'honours ?limit= and clamps' do
    20.times { |i| make_player(slug: "p#{i}", full_name: "P#{i}", tour: 'atp', current_rank: i + 1) }
    get '/sports/tennis?limit=5'
    expect(last_response.body.scan(/<a class="sports-tennis-name"/).length).to eq(5)
  end
end

RSpec.describe '/sports/player/:slug' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'renders the player detail page' do
    make_player(slug: 'jannik-sinner', full_name: 'Jannik Sinner',
                tour: 'atp', current_rank: 1, previous_rank: 1,
                points: 14350.0, country: 'ITA',
                headshot_url: 'https://h/sinner.png',
                external_id: '3623')
    get '/sports/player/jannik-sinner'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Jannik Sinner')
    expect(last_response.body).to include('ITA')
    expect(last_response.body).to include('Current rank')
    expect(last_response.body).to include('14350')
    # External ESPN profile link present.
    expect(last_response.body).to include('https://www.espn.com/tennis/player/_/id/3623/jannik-sinner')
  end

  it '404s on an unknown slug' do
    get '/sports/player/nobody'
    expect(last_response.status).to eq(404)
  end

  it 'shows movement (rising) when previous_rank > current_rank' do
    make_player(slug: 'mover', full_name: 'Mover', tour: 'atp',
                current_rank: 3, previous_rank: 7)
    get '/sports/player/mover'
    expect(last_response.body).to match(/&uarr; 4 from 7/)
  end
end

RSpec.describe '/sports header tennis link' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'shows a "Tennis rankings →" link in the /sports subtitle when feeds are subscribed' do
    FeedsStore.add(url: 'https://www.bleedinggreennation.com/rss/index.xml', title: 'BGN', topic: 'sports')
    get '/sports'
    expect(last_response.body).to include('href="/sports/tennis"')
    expect(last_response.body).to include('Tennis rankings')
  end
end
