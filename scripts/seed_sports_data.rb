#!/usr/bin/env ruby
# Seed sports_leagues + sports_teams + sports_follows for the
# user's followed teams. Idempotent — safe to re-run after every
# migration.
#
# Coverage in v1: Eagles, Sixers, Union, All Blacks (men's intl
# rugby). Black Ferns + Tennis structured data is deferred — both
# need TheSportsDB or similar, and the free TheSportsDB key is
# poisoned. Their RSS news pipeline is unaffected.
#
# Usage:
#   make seed-sports-data
#   bundle exec ruby scripts/seed_sports_data.rb

require_relative '../app/credentials'
require_relative '../app/database'
require_relative '../app/sports_leagues_store'
require_relative '../app/sports_teams_store'
require_relative '../app/sports_follows_store'

Database.migrate!

# Leagues — ESPN sport_path doubles as external_id. The /scoreboard
# and /teams/<id>/schedule endpoints both key off this path.
LEAGUES = [
  { slug: 'nfl',         name: 'NFL',                 sport: 'football',
    source_provider: 'espn', external_id: 'football/nfl',   country: 'US' },
  { slug: 'nba',         name: 'NBA',                 sport: 'basketball',
    source_provider: 'espn', external_id: 'basketball/nba', country: 'US' },
  { slug: 'mls',         name: 'Major League Soccer', sport: 'soccer',
    source_provider: 'espn', external_id: 'soccer/usa.1',   country: 'US' },
  { slug: 'intl-rugby',  name: 'International Rugby (test matches)', sport: 'rugby',
    source_provider: 'espn', external_id: 'rugby/164205',   country: nil }
].freeze

# Teams — keyed to the league we just seeded. ESPN team IDs were
# verified live at seed-design time (probe captured in the PR
# discussion).
TEAMS = [
  { slug: 'eagles',     name: 'Philadelphia Eagles', short_name: 'Eagles',
    location: 'Philadelphia', league_slug: 'nfl',
    source_provider: 'espn', external_id: '21' },
  { slug: 'sixers',     name: 'Philadelphia 76ers',  short_name: 'Sixers',
    location: 'Philadelphia', league_slug: 'nba',
    source_provider: 'espn', external_id: '20' },
  { slug: 'union',      name: 'Philadelphia Union',  short_name: 'Union',
    location: 'Philadelphia', league_slug: 'mls',
    source_provider: 'espn', external_id: '10739' },
  { slug: 'all-blacks', name: 'New Zealand',         short_name: 'All Blacks',
    location: 'New Zealand',  league_slug: 'intl-rugby',
    source_provider: 'espn', external_id: '8' }
].freeze

FOLLOWS = TEAMS.map { |t| { kind: 'team', value: t[:slug] } }.freeze

leagues_by_slug = {}

LEAGUES.each do |spec|
  league = SportsLeaguesStore.upsert(
    slug:            spec[:slug],
    name:            spec[:name],
    sport:           spec[:sport],
    source_provider: spec[:source_provider],
    external_id:     spec[:external_id],
    country:         spec[:country]
  )
  leagues_by_slug[spec[:slug]] = league
  puts "  league  #{spec[:slug].ljust(12)} → id=#{league['id']}"
end

TEAMS.each do |spec|
  league = leagues_by_slug.fetch(spec[:league_slug])
  team = SportsTeamsStore.upsert(
    league_id:       league['id'],
    slug:            spec[:slug],
    name:            spec[:name],
    short_name:      spec[:short_name],
    location:        spec[:location],
    source_provider: spec[:source_provider],
    external_id:     spec[:external_id]
  )
  puts "  team    #{spec[:slug].ljust(12)} → id=#{team['id']} league=#{spec[:league_slug]}"
end

FOLLOWS.each do |spec|
  added = SportsFollowsStore.add(kind: spec[:kind], value: spec[:value])
  puts "  follow  #{spec[:kind]}:#{spec[:value].ljust(12)} #{added ? '(new)' : '(already followed)'}"
end

puts
puts "Done. leagues=#{SportsLeaguesStore.count} teams=#{SportsTeamsStore.count} follows=#{SportsFollowsStore.count}"
