require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/sports_leagues_store'
require_relative '../app/sports_teams_store'
require_relative '../app/sports_matches_store'
require_relative '../app/sports_follows_store'

# Sports Phase S9 — calendar view + iCal export.
#
# Covers four surfaces:
#   1. SportsMatchesStore.upcoming_for_followed_teams(1, 1) (DB query)
#   2. /sports/calendar HTML view
#   3. /sports/calendar.ics export (RFC 5545 structure)
#   4. The "Calendar →" link from /sports

# Use a wider helper than the standings spec — we need a fully-
# wired league + team + match + follow so the upcoming query
# pulls it in.
def setup_followed_match(scheduled_at:, sport: 'football', league_slug: 'nfl',
                          team_slug: 'eagles', team_name: 'Philadelphia Eagles',
                          opponent_name: 'Dallas Cowboys', venue: 'Lincoln Financial Field',
                          status: 'scheduled')
  league = SportsLeaguesStore.upsert(slug: league_slug, name: league_slug.upcase, sport: sport,
                                      source_provider: 'espn', external_id: "#{sport}/#{league_slug}")
  home   = SportsTeamsStore.upsert(league_id: league['id'], slug: team_slug, name: team_name,
                                    short_name: team_name.split.last, source_provider: 'espn',
                                    external_id: '21', image_url: 'https://logo.example/team.png')
  away   = SportsTeamsStore.upsert(league_id: league['id'], slug: "#{league_slug}-team-6",
                                    name: opponent_name, source_provider: 'espn',
                                    external_id: '6', image_url: 'https://logo.example/opp.png')
  match  = SportsMatchesStore.upsert(
    league_id: league['id'], source_provider: 'espn',
    external_id: "evt-#{scheduled_at}",
    scheduled_at: scheduled_at, status: status,
    home_team_id: home['id'], away_team_id: away['id'],
    venue: venue
  )
  SportsFollowsStore.add(user_id: 1, kind: 'team', value: team_slug)
  [league, home, away, match]
end

RSpec.describe SportsMatchesStore, '.upcoming_for_followed_teams' do
  let(:now) { Time.parse('2026-05-01T00:00Z').utc }

  it 'returns scheduled matches for followed teams within the window' do
    setup_followed_match(scheduled_at: '2026-05-05T00:00Z')
    matches = SportsMatchesStore.upcoming_for_followed_teams(1, days_forward: 30, now: now)
    expect(matches.length).to eq(1)
  end

  it 'excludes matches outside the days_forward window' do
    setup_followed_match(scheduled_at: '2027-01-01T00:00Z') # 8 months out
    matches = SportsMatchesStore.upcoming_for_followed_teams(1, days_forward: 30, now: now)
    expect(matches).to be_empty
  end

  it 'excludes matches in the past' do
    setup_followed_match(scheduled_at: '2026-04-01T00:00Z') # before now
    expect(SportsMatchesStore.upcoming_for_followed_teams(1, days_forward: 30, now: now)).to be_empty
  end

  it 'excludes matches whose status is final / cancelled / postponed' do
    setup_followed_match(scheduled_at: '2026-05-05T00:00Z', status: 'final')
    expect(SportsMatchesStore.upcoming_for_followed_teams(1, days_forward: 30, now: now)).to be_empty
  end

  it 'includes live matches' do
    setup_followed_match(scheduled_at: '2026-05-05T00:00Z', status: 'live')
    expect(SportsMatchesStore.upcoming_for_followed_teams(1, days_forward: 30, now: now).length).to eq(1)
  end

  it 'excludes matches for unfollowed teams' do
    league = SportsLeaguesStore.upsert(slug: 'nfl', name: 'NFL', sport: 'football',
                                        source_provider: 'espn', external_id: 'football/nfl')
    team   = SportsTeamsStore.upsert(league_id: league['id'], slug: 'cowboys', name: 'Dallas Cowboys',
                                      source_provider: 'espn', external_id: '6')
    SportsMatchesStore.upsert(
      league_id: league['id'], source_provider: 'espn', external_id: 'evt-1',
      scheduled_at: '2026-05-05T00:00Z', status: 'scheduled',
      home_team_id: team['id']
    )
    # No follow — should not surface.
    expect(SportsMatchesStore.upcoming_for_followed_teams(1, days_forward: 30, now: now)).to be_empty
  end

  it 'orders matches chronologically (soonest first)' do
    setup_followed_match(scheduled_at: '2026-05-10T00:00Z')
    setup_followed_match(scheduled_at: '2026-05-05T00:00Z',
                          team_slug: 'sixers', team_name: 'Philadelphia 76ers',
                          league_slug: 'nba', sport: 'basketball')
    matches = SportsMatchesStore.upcoming_for_followed_teams(1, days_forward: 30, now: now)
    expect(matches.first['scheduled_at']).to eq('2026-05-05T00:00Z')
    expect(matches.last['scheduled_at']).to  eq('2026-05-10T00:00Z')
  end
end

RSpec.describe 'GET /sports/calendar' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'renders the empty state when no follows have upcoming fixtures' do
    get '/sports/calendar'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('No upcoming fixtures')
  end

  it 'renders the subscribe-URL callout' do
    setup_followed_match(scheduled_at: (Time.now.utc + 86400).iso8601)
    get '/sports/calendar'
    expect(last_response.body).to include('Subscribe to this calendar')
    expect(last_response.body).to include('/sports/calendar.ics')
  end

  it 'groups fixtures by day, soonest first' do
    setup_followed_match(scheduled_at: (Time.now.utc + 2 * 86400).iso8601)
    setup_followed_match(
      scheduled_at: (Time.now.utc + 1 * 86400).iso8601,
      team_slug: 'sixers', team_name: 'Philadelphia 76ers',
      league_slug: 'nba', sport: 'basketball'
    )
    get '/sports/calendar'
    body = last_response.body
    expect(body.scan(%r{<section class="benchmark-section sports-calendar-day}).length).to eq(2)
    sixers_pos = body.index('Philadelphia 76ers')
    eagles_pos = body.index('Philadelphia Eagles')
    expect(sixers_pos).to be < eagles_pos # earlier day first
  end

  it 'links every team chip to /sports/team/:slug (STUFF #71)' do
    setup_followed_match(scheduled_at: (Time.now.utc + 86400).iso8601)
    get '/sports/calendar'
    # Eagles — curated SportsTeams entry, links as before.
    expect(last_response.body).to include('href="/sports/team/eagles"')
    # Cowboys auto-created opponent — STUFF #67 made /sports/team/:slug
    # fall back to SportsTeamsStore.find_by_slug, so this slug now
    # links too (was a plain span pre-#71).
    expect(last_response.body).to include('href="/sports/team/nfl-team-6"')
  end

  it 'honours ?days= and clamps to 1..365' do
    setup_followed_match(scheduled_at: (Time.now.utc + 200 * 86400).iso8601) # 200 days out
    get '/sports/calendar' # default 30
    expect(last_response.body).not_to include('Philadelphia Eagles')

    get '/sports/calendar?days=365'
    expect(last_response.body).to include('Philadelphia Eagles')
  end
end

RSpec.describe 'GET /sports/calendar.ics' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'returns a text/calendar Content-Type' do
    setup_followed_match(scheduled_at: (Time.now.utc + 86400).iso8601)
    get '/sports/calendar.ics'
    expect(last_response.status).to eq(200)
    expect(last_response.content_type).to start_with('text/calendar')
    expect(last_response.headers['Content-Disposition']).to include('tech-feed-reader-sports.ics')
  end

  it 'wraps in BEGIN:VCALENDAR / END:VCALENDAR with required headers' do
    setup_followed_match(scheduled_at: (Time.now.utc + 86400).iso8601)
    get '/sports/calendar.ics'
    body = last_response.body
    expect(body).to start_with('BEGIN:VCALENDAR')
    expect(body).to include('VERSION:2.0')
    expect(body).to include('PRODID:')
    expect(body.strip).to end_with('END:VCALENDAR')
  end

  it 'uses CRLF line endings (RFC 5545)' do
    setup_followed_match(scheduled_at: (Time.now.utc + 86400).iso8601)
    get '/sports/calendar.ics'
    expect(last_response.body).to include("\r\n")
  end

  it 'emits one VEVENT per upcoming match with UID/DTSTAMP/DTSTART/DTEND/SUMMARY' do
    setup_followed_match(scheduled_at: (Time.now.utc + 86400).iso8601, venue: 'The Linc')
    get '/sports/calendar.ics'
    body = last_response.body
    expect(body.scan('BEGIN:VEVENT').length).to eq(1)
    expect(body.scan('END:VEVENT').length).to eq(1)
    expect(body).to match(/UID:tfr-sports-match-\d+@tech-feed-reader/)
    expect(body).to match(/DTSTAMP:\d{8}T\d{6}Z/)
    expect(body).to match(/DTSTART:\d{8}T\d{6}Z/)
    expect(body).to match(/DTEND:\d{8}T\d{6}Z/)
    expect(body).to include('SUMMARY:Dallas Cowboys @ Philadelphia Eagles')
    expect(body).to include('LOCATION:The Linc')
    expect(body).to include('STATUS:TENTATIVE')
  end

  it 'marks live matches with STATUS:CONFIRMED' do
    setup_followed_match(scheduled_at: (Time.now.utc + 60).iso8601, status: 'live')
    get '/sports/calendar.ics'
    expect(last_response.body).to include('STATUS:CONFIRMED')
  end

  it 'escapes commas / semicolons / newlines in TEXT properties (RFC 5545)' do
    setup_followed_match(
      scheduled_at: (Time.now.utc + 86400).iso8601,
      venue: 'Stadium, with comma; and semicolon'
    )
    get '/sports/calendar.ics'
    body = last_response.body
    expect(body).to include('LOCATION:Stadium\\, with comma\\; and semicolon')
  end

  it 'sets DTEND duration based on the league sport' do
    # NBA → 2.5h offset. Pick a date 5 days in the future so the
    # default 30-day window catches it.
    target = (Time.now.utc + 5 * 86_400).strftime('%Y-%m-%dT21:30:00Z')
    setup_followed_match(
      scheduled_at: target, sport: 'basketball', league_slug: 'nba',
      team_slug: 'sixers', team_name: 'Philadelphia 76ers',
      opponent_name: 'Boston Celtics', venue: 'TD Garden'
    )
    get '/sports/calendar.ics'
    body = last_response.body
    # Find the DTSTART/DTEND values; expect DTEND to be 2.5h
    # after DTSTART (next-day 00:00 because 21:30 + 2.5h = 24:00).
    dtstart = body[/DTSTART:(\d{8}T\d{6}Z)/, 1]
    dtend   = body[/DTEND:(\d{8}T\d{6}Z)/,   1]
    expect(dtstart).not_to be_nil
    expect(dtend).not_to   be_nil
    diff_seconds = Time.strptime(dtend, '%Y%m%dT%H%M%SZ') - Time.strptime(dtstart, '%Y%m%dT%H%M%SZ')
    expect(diff_seconds).to eq(2.5 * 3600) # NBA default
  end
end

RSpec.describe '/sports header Calendar link' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'shows a "Calendar →" link in the header subtitle when the user has feeds' do
    FeedsStore.add(url: 'https://www.bleedinggreennation.com/rss/index.xml',
                    title: 'BGN', topic: 'sports')
    get '/sports'
    expect(last_response.body).to include('href="/sports/calendar"')
    expect(last_response.body).to include('Calendar &rarr;')
  end
end
