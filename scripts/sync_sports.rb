#!/usr/bin/env ruby
# Sports Phase S4 cron entry point — pulls match data from
# Providers::ESPN for every followed team and upserts into
# sports_matches.
#
# Idempotent — re-running never duplicates rows (upsert keys on
# (source_provider, external_id)).
#
# Strategy per team:
#   - NFL / NBA / MLS: team_schedule endpoint returns the entire
#     season's schedule, finals + scheduled in one call. Cheap.
#   - International rugby: team_schedule 500s. Use the
#     league_scoreboard endpoint without dates, which returns the
#     current/upcoming window. Filter to events involving the
#     followed team.
#
# Usage:
#   make sync-sports
#   bundle exec ruby scripts/sync_sports.rb
#
# Pair with launchd / cron (daily, e.g. 04:00 local — after the
# previous day's games have finalised):
#   0 4 * * *  cd /Users/outten/src/tech-feed-reader && \
#              /Users/outten/.rvm/wrappers/ruby-3.4.1/bundle exec \
#              ruby scripts/sync_sports.rb >> tmp/logs/sports_sync.log 2>&1

require_relative '../app/credentials'
require_relative '../app/database'
require_relative '../app/sports_leagues_store'
require_relative '../app/sports_teams_store'
require_relative '../app/sports_matches_store'
require_relative '../app/sports_follows_store'
require_relative '../app/providers/espn'
require_relative '../app/logger'

Database.migrate!

followed_team_slugs = SportsFollowsStore.for_kind('team').map { |f| f['value'] }
if followed_team_slugs.empty?
  puts 'No team follows yet — run `make seed-sports-data` first or follow teams via the UI.'
  exit 0
end

# Sports for which the per-team schedule endpoint is reliable.
# Rugby is excluded — it 500s on /teams/<id>/schedule.
TEAM_SCHEDULE_SPORTS = %w[football basketball soccer].freeze

upserted = 0
skipped  = 0

followed_team_slugs.each do |slug|
  team = SportsTeamsStore.find_by_slug(slug)
  unless team
    warn "  follow:#{slug} has no matching sports_teams row — skip (run `make seed-sports-data`?)"
    skipped += 1
    next
  end

  league = SportsLeaguesStore.find(team['league_id'])
  unless league
    warn "  team:#{slug} → orphaned league_id=#{team['league_id']} — skip"
    skipped += 1
    next
  end

  matches =
    if TEAM_SCHEDULE_SPORTS.include?(league['sport']) && league['source_provider'] == 'espn'
      Providers::ESPN.team_schedule(
        sport_path:       league['external_id'],
        team_external_id: team['external_id']
      )
    elsif league['sport'] == 'rugby' && league['source_provider'] == 'espn'
      events = Providers::ESPN.league_scoreboard(sport_path: league['external_id'])
      events.select do |m|
        m.home_team_external_id == team['external_id'] ||
          m.away_team_external_id == team['external_id']
      end
    else
      AppLogger.warn('sync_sports', status: :unsupported, slug: slug,
                                     sport: league['sport'], provider: league['source_provider'])
      []
    end

  # Auto-upsert opponent teams so matches can reference both sides.
  # Without this, only the user's followed team shows in match rows
  # and the opponent appears blank in the (forthcoming) UI. Cheap —
  # NFL has 32 teams, NBA has 30, MLS has ~30. SportsTeamsStore
  # upsert is idempotent on (source, external_id).
  ensure_opponent = ->(m, side_external_id, side_name) do
    return if side_external_id.nil? || side_external_id.empty?
    existing_opponent = SportsTeamsStore.find_by_external(league['source_provider'], side_external_id)
    return existing_opponent if existing_opponent
    opponent_slug = "#{league['slug']}-team-#{side_external_id}"
    SportsTeamsStore.upsert(
      league_id:       league['id'],
      slug:            opponent_slug,
      name:            side_name.to_s.empty? ? opponent_slug : side_name,
      short_name:      nil,
      source_provider: league['source_provider'],
      external_id:     side_external_id
    )
  end

  matches.each do |m|
    ensure_opponent.call(m, m.home_team_external_id, m.home_team_name)
    ensure_opponent.call(m, m.away_team_external_id, m.away_team_name)
    home_team = SportsTeamsStore.find_by_external(league['source_provider'], m.home_team_external_id)
    away_team = SportsTeamsStore.find_by_external(league['source_provider'], m.away_team_external_id)
    SportsMatchesStore.upsert(
      league_id:       league['id'],
      source_provider: league['source_provider'],
      external_id:     m.external_id,
      scheduled_at:    m.scheduled_at,
      status:          m.status,
      home_team_id:    home_team && home_team['id'],
      away_team_id:    away_team && away_team['id'],
      home_score:      m.home_score,
      away_score:      m.away_score,
      period:          m.period,
      venue:           m.venue
    )
    upserted += 1
  end

  puts "  team:#{slug.ljust(12)} matches=#{matches.length}"
end

puts
puts "Done. upserted=#{upserted} skipped=#{skipped} matches_total=#{SportsMatchesStore.count}"
