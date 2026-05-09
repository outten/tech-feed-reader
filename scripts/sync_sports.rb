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
require_relative '../app/sports_standings_store'
require_relative '../app/sports_players_store'
require_relative '../app/sports_follows_store'
require_relative '../app/providers/espn'
require_relative '../app/logger'

# slugify a tennis player display name. "Iga Świątek" → "iga-swiatek".
# Strips diacritics by best-effort using ASCII transliteration via
# Unicode decomposition.
def tennis_player_slug(full_name)
  s = full_name.to_s.unicode_normalize(:nfd).gsub(/[^\x00-\x7F]/, '')
  s = s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/(^-|-$)/, '')
  s.empty? ? nil : s
end

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
  ensure_team = ->(side_external_id, side_name, side_logo) do
    return if side_external_id.nil? || side_external_id.empty?
    existing = SportsTeamsStore.find_by_external(league['source_provider'], side_external_id, league_id: league['id'])
    if existing
      # Backfill image_url + name if the existing row is missing them
      # (newly-followed teams seeded earlier have name but no logo).
      should_update = (existing['image_url'].to_s.empty? && !side_logo.to_s.empty?) ||
                      (existing['name'].to_s.empty?      && !side_name.to_s.empty?)
      return existing unless should_update
      SportsTeamsStore.upsert(
        league_id:       existing['league_id'],
        slug:            existing['slug'],
        name:            existing['name'].to_s.empty? ? side_name : existing['name'],
        short_name:      existing['short_name'],
        location:        existing['location'],
        source_provider: existing['source_provider'],
        external_id:     existing['external_id'],
        image_url:       existing['image_url'].to_s.empty? ? side_logo : existing['image_url']
      )
    else
      opponent_slug = "#{league['slug']}-team-#{side_external_id}"
      SportsTeamsStore.upsert(
        league_id:       league['id'],
        slug:            opponent_slug,
        name:            side_name.to_s.empty? ? opponent_slug : side_name,
        short_name:      nil,
        source_provider: league['source_provider'],
        external_id:     side_external_id,
        image_url:       side_logo
      )
    end
  end

  matches.each do |m|
    ensure_team.call(m.home_team_external_id, m.home_team_name, m.home_team_logo)
    ensure_team.call(m.away_team_external_id, m.away_team_name, m.away_team_logo)
    home_team = SportsTeamsStore.find_by_external(league['source_provider'], m.home_team_external_id, league_id: league['id'])
    away_team = SportsTeamsStore.find_by_external(league['source_provider'], m.away_team_external_id, league_id: league['id'])
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

# Phase S8 — sync league standings for every seeded ESPN league.
# Wider than the match sync (which is follow-gated): standings are
# globally interesting (e.g. World Cup standings even when the
# user follows no specific national team), and the call is cheap
# (one HTTP per league). The /sports "By league:" TOC gates
# visibility to leagues that have synced standings, so this is
# what determines what's discoverable from the overview page.
puts
puts "Syncing standings…"
standings_count = 0

SportsLeaguesStore.all.each do |league|
  next unless league['source_provider'] == 'espn'

  groups = Providers::ESPN.standings(sport_path: league['external_id'])
  groups.each do |group|
    group.entries.each_with_index do |entry, idx|
      team_row = SportsTeamsStore.find_by_external(
        league['source_provider'], entry.team_external_id, league_id: league['id']
      )
      # Auto-create the team row if missing (rare — the schedule
      # sync already creates opponents). image_url backfilled too.
      team_row ||= SportsTeamsStore.upsert(
        league_id:       league['id'],
        slug:            "#{league['slug']}-team-#{entry.team_external_id}",
        name:            entry.team_name.to_s.empty? ? entry.team_external_id : entry.team_name,
        source_provider: league['source_provider'],
        external_id:     entry.team_external_id,
        image_url:       entry.team_logo
      )

      SportsStandingsStore.upsert(
        league_id:           league['id'],
        team_id:             team_row['id'],
        group_name:          group.group_name,
        source_provider:     league['source_provider'],
        position:            entry.position || (idx + 1),
        wins:                entry.wins,
        losses:              entry.losses,
        ties:                entry.ties,
        win_percent:         entry.win_percent,
        points_for:          entry.points_for,
        points_against:      entry.points_against,
        point_differential:  entry.point_differential,
        games_behind:        entry.games_behind,
        streak:              entry.streak,
        playoff_seed:        entry.playoff_seed
      )
      standings_count += 1
    end
  end
  puts "  league:#{league['slug'].ljust(12)} groups=#{groups.length} entries=#{groups.sum { |g| g.entries.length }}"
end

# Phase S7 — tennis rankings (ATP + WTA top 150 each). Cheap (one
# HTTP per tour). Runs unconditionally; rankings are globally
# interesting and don't require a follow.
puts
puts "Syncing tennis rankings…"
tennis_count = 0
%w[atp wta].each do |tour|
  entries = Providers::ESPN.tennis_rankings(tour: tour)
  entries.each do |e|
    slug = tennis_player_slug(e.full_name)
    next unless slug && e.athlete_external_id && !e.athlete_external_id.empty?
    SportsPlayersStore.upsert(
      sport:           'tennis',
      slug:            slug,
      full_name:       e.full_name,
      country:         e.country,
      image_url:       e.headshot_url,
      tour:            e.tour,
      current_rank:    e.current_rank,
      previous_rank:   e.previous_rank,
      points:          e.points,
      trend:           e.trend,
      headshot_url:    e.headshot_url,
      flag_url:        e.flag_url,
      source_provider: 'espn',
      external_id:     e.athlete_external_id
    )
    tennis_count += 1
  end
  puts "  tour:#{tour.upcase.ljust(12)} ranked=#{entries.length}"
end

puts
puts "Done. matches_upserted=#{upserted} matches_total=#{SportsMatchesStore.count} standings_total=#{SportsStandingsStore.count} players_total=#{SportsPlayersStore.count}"
