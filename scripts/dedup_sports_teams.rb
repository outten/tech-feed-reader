#!/usr/bin/env ruby
# frozen_string_literal: true

# STUFF #68 — one-shot backfill that collapses duplicate sports_teams
# rows created by the pre-fix sync path. Before this PR, the ESPN
# sync ALWAYS auto-created a `<league>-team-<external_id>` row when
# its find_by_external missed — which it did on first sync for every
# team in a league not in scripts/seed_sports_data.rb's
# CATALOG_LEAGUES list (NFL/NBA/MLS). MLB is the visible victim
# (Phillies / Dodgers / Mets etc. exist twice: once as the manually-
# seeded catalog row, once as `mlb-team-22` etc. with all the
# matches/standings/follows pointing at one half or the other).
#
# This script finds pairs of rows that:
#   - share the same (league_id, LOWER(name))
#   - one has source_provider != 'espn' (the "natural" catalog row)
#   - the other has source_provider = 'espn' with an auto slug
#     matching `<league_slug>-team-<external_id>`
# and:
#   - moves sports_matches.home_team_id / away_team_id pointers
#   - moves sports_standings.team_id pointers
#   - moves sports_entity_articles where kind='team' + entity_id
#   - rewrites sports_follows.value where it equals the auto slug
#   - promotes the catalog row to source_provider='espn' with the
#     ESPN external_id and image_url (so future syncs hit the
#     existing row via find_by_external)
#   - deletes the now-empty auto-slug row
#
# Idempotent: re-running after a clean dedup finds nothing to do.
#
# Usage:
#   bundle exec ruby scripts/dedup_sports_teams.rb [--apply]
#
# Without --apply, prints a dry-run plan and exits 0.

ENV['RACK_ENV'] ||= 'development'
require_relative '../app/credentials'
require_relative '../app/database'
require_relative '../app/sports_teams_store'
require_relative '../app/sports_leagues_store'
require_relative '../app/sports_follows_store'

APPLY = ARGV.include?('--apply')

db = Database.connection

# Find duplicate (league_id, name) pairs where one row has an ESPN
# auto-slug and the other has a natural slug.
pairs = db.execute(<<~SQL).group_by { |r| [r['league_id'], r['name'].downcase] }
  SELECT id, league_id, slug, name, source_provider, external_id, image_url
  FROM sports_teams
SQL

dedup_targets = []
pairs.each do |(league_id, name), rows|
  next if rows.length < 2
  league = SportsLeaguesStore.find(league_id)
  next unless league
  auto_pattern = "#{league['slug']}-team-"
  natural = rows.find { |r| !r['slug'].to_s.start_with?(auto_pattern) }
  auto    = rows.find { |r| r['slug'].to_s.start_with?(auto_pattern) }
  next unless natural && auto
  dedup_targets << { natural: natural, auto: auto, league: league, display_name: name }
end

if dedup_targets.empty?
  puts 'No duplicates found. Nothing to do.'
  exit 0
end

puts "Found #{dedup_targets.length} duplicate team pair#{'s' unless dedup_targets.length == 1}:"
dedup_targets.each do |t|
  puts "  [#{t[:league]['slug'].ljust(10)}] #{t[:display_name]}: keep #{t[:natural]['slug']} (id=#{t[:natural]['id']}), drop #{t[:auto]['slug']} (id=#{t[:auto]['id']})"
end

unless APPLY
  puts
  puts 'Dry run only. Re-run with --apply to merge.'
  exit 0
end

puts
puts 'Applying merges...'

dedup_targets.each do |t|
  natural_id = t[:natural]['id']
  auto_id    = t[:auto]['id']
  auto_slug  = t[:auto]['slug']

  db.transaction do
    # 1. sports_matches: redirect home + away pointers. The unique
    #    constraint is on (source_provider, external_id), not on
    #    (home_team_id, away_team_id), so a plain UPDATE is safe.
    db.execute('UPDATE sports_matches SET home_team_id = ? WHERE home_team_id = ?',
               [natural_id, auto_id])
    db.execute('UPDATE sports_matches SET away_team_id = ? WHERE away_team_id = ?',
               [natural_id, auto_id])

    # 2. sports_standings: redirect team_id. The auto + natural
    #    rows can BOTH have a standings entry for the same
    #    (source_provider, league_id, group_name) — moving the
    #    auto entry would violate the unique constraint. Strategy:
    #    if a natural-row standings entry already exists, just
    #    drop the auto one; otherwise rewrite the FK in place.
    db.execute(<<~SQL, [auto_id, natural_id])
      DELETE FROM sports_standings
      WHERE team_id = ?
        AND EXISTS (
          SELECT 1 FROM sports_standings s2
          WHERE s2.source_provider = sports_standings.source_provider
            AND s2.league_id       = sports_standings.league_id
            AND s2.group_name      IS NOT DISTINCT FROM sports_standings.group_name
            AND s2.team_id         = ?
        )
    SQL
    db.execute('UPDATE sports_standings SET team_id = ? WHERE team_id = ?',
               [natural_id, auto_id])

    # 3. sports_entity_articles: PK is (kind, entity_id, article_id).
    #    The auto-row entries that already have a matching
    #    natural-row entry would collide on UPDATE — INSERT…SELECT
    #    with ON CONFLICT DO NOTHING merges only the new ones, then
    #    DELETE drops the rest.
    db.execute(<<~SQL, [natural_id, auto_id])
      INSERT INTO sports_entity_articles (kind, entity_id, article_id, matched_at)
      SELECT kind, ?, article_id, matched_at
      FROM sports_entity_articles
      WHERE kind = 'team' AND entity_id = ?
      ON CONFLICT (kind, entity_id, article_id) DO NOTHING
    SQL
    db.execute("DELETE FROM sports_entity_articles WHERE kind = 'team' AND entity_id = ?",
               [auto_id])

    # 4. sports_follows: rewrite slug value (idempotent: skip if user
    #    already follows the natural slug too, otherwise just rename).
    follows_to_dedup = db.execute(
      "SELECT user_id FROM sports_follows WHERE kind='team' AND value = ?",
      [auto_slug]
    )
    follows_to_dedup.each do |row|
      uid = row['user_id']
      already_follows_natural = db.execute(
        "SELECT 1 FROM sports_follows WHERE user_id = ? AND kind = 'team' AND value = ?",
        [uid, t[:natural]['slug']]
      ).any?
      if already_follows_natural
        db.execute("DELETE FROM sports_follows WHERE user_id = ? AND kind = 'team' AND value = ?",
                   [uid, auto_slug])
      else
        db.execute("UPDATE sports_follows SET value = ? WHERE user_id = ? AND kind = 'team' AND value = ?",
                   [t[:natural]['slug'], uid, auto_slug])
      end
    end

    # 5. Delete the now-empty auto row FIRST so its
    #    (source_provider, league_id, external_id) tuple is free,
    #    THEN promote the natural row into that identity. Doing it
    #    in the other order trips the unique constraint on
    #    sports_teams_source_provider_league_id_external_id_key.
    db.execute('DELETE FROM sports_teams WHERE id = ?', [auto_id])

    # 6. Promote the natural row to ESPN-tracked.
    promoted_image = t[:auto]['image_url'].to_s.empty? ? t[:natural]['image_url'] : t[:auto]['image_url']
    db.execute(<<~SQL, [t[:auto]['source_provider'], t[:auto]['external_id'], promoted_image, natural_id])
      UPDATE sports_teams
      SET source_provider = ?, external_id = ?, image_url = ?
      WHERE id = ?
    SQL
  end

  puts "  merged #{auto_slug} → #{t[:natural]['slug']}"
end

puts
puts 'Done.'
