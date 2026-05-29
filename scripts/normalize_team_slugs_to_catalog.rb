#!/usr/bin/env ruby
# frozen_string_literal: true

# STUFF #69 — one-shot backfill that aligns sports_teams.slug with
# the canonical slug declared in app/sports_catalog.rb.
#
# Why this exists: when the ESPN standings sync sees a team for the
# first time it auto-creates a row with slug `<league>-team-<external_id>`
# (e.g. `nba-team-13` for the Lakers). Later, when a user clicks
# "+ Follow" on /sports/manage/basketball/nba, the form POSTs the
# CATALOG slug (`lakers`). The pre-#69 follow handler called
# SportsTeamsStore.upsert which finds the existing row by
# (source_provider, external_id) and updates name/image — but never
# touches the slug column. Result: sports_follows.value='lakers' has
# no matching sports_teams.slug, so the team never surfaces on
# /sports.
#
# Strategy: walk SportsCatalog.all_teams. For each catalog team, look
# up the DB row by (catalog source_provider, catalog external_id,
# catalog league_id). If found with a different slug, rename it to
# the catalog slug. Also rewrite any sports_follows.value entries
# from the old slug to the new (de-dup if the user already follows
# both halves of the rename).
#
# Idempotent: re-running after a clean normalization finds nothing
# to do. FKs in sports_matches / sports_standings / sports_entity_
# articles point at sports_teams.id so the rename is safe without
# touching them.
#
# Usage:
#   bundle exec ruby scripts/normalize_team_slugs_to_catalog.rb
#   bundle exec ruby scripts/normalize_team_slugs_to_catalog.rb --apply

ENV['RACK_ENV'] ||= 'development'
require_relative '../app/credentials'
require_relative '../app/database'
require_relative '../app/sports_catalog'
require_relative '../app/sports_teams_store'
require_relative '../app/sports_leagues_store'

APPLY = ARGV.include?('--apply')

renames = []

SportsCatalog.all_teams.each do |catalog_team|
  catalog_league = SportsCatalog.find_league(catalog_team[:sport_slug], catalog_team[:league_slug])
  next unless catalog_league

  # Resolve the league's DB id without upserting it — if the league
  # doesn't exist in the DB yet, no team rows can exist for it
  # either and there's nothing to rename.
  league = SportsLeaguesStore.find_by_external(
    catalog_league[:source_provider] || 'catalog',
    catalog_league[:external_id]     || catalog_league[:slug]
  )
  next unless league

  provider    = catalog_team[:source_provider] || 'catalog'
  external_id = catalog_team[:external_id]     || catalog_team[:slug]
  existing    = SportsTeamsStore.find_by_external(provider, external_id, league_id: league['id'])
  next unless existing
  next if existing['slug'] == catalog_team[:slug]

  # Sanity: don't clobber a row that already lives at the target
  # slug (would violate the UNIQUE constraint on sports_teams.slug).
  # In practice this would mean two DB rows for the same team; the
  # dedup script (STUFF #68) is the tool for that case.
  conflict = SportsTeamsStore.find_by_slug(catalog_team[:slug])
  if conflict && conflict['id'] != existing['id']
    puts "  SKIP #{existing['slug']} → #{catalog_team[:slug]} (conflict: existing row id=#{conflict['id']}); run dedup_sports_teams.rb first"
    next
  end

  renames << { existing: existing, catalog_slug: catalog_team[:slug] }
end

if renames.empty?
  puts 'No slug renames needed. Nothing to do.'
  exit 0
end

puts "Found #{renames.length} team#{'s' unless renames.length == 1} whose slug differs from the catalog:"
renames.each do |r|
  puts "  rename #{r[:existing]['slug'].ljust(18)} → #{r[:catalog_slug].ljust(18)} (#{r[:existing]['name']})"
end

unless APPLY
  puts
  puts 'Dry run only. Re-run with --apply to commit.'
  exit 0
end

puts
puts 'Applying renames...'

db = Database.connection

renames.each do |r|
  existing_id  = r[:existing]['id']
  old_slug     = r[:existing]['slug']
  new_slug     = r[:catalog_slug]

  db.transaction do
    SportsTeamsStore.rename_slug!(existing_id, new_slug)

    # Move sports_follows entries to the canonical slug. If the user
    # follows both halves of the rename, drop the auto-slug version.
    follows = db.execute(
      "SELECT user_id FROM sports_follows WHERE kind='team' AND value = ?",
      [old_slug]
    )
    follows.each do |row|
      uid = row['user_id']
      already_canonical = db.execute(
        "SELECT 1 FROM sports_follows WHERE user_id = ? AND kind = 'team' AND value = ?",
        [uid, new_slug]
      ).any?
      if already_canonical
        db.execute("DELETE FROM sports_follows WHERE user_id = ? AND kind = 'team' AND value = ?",
                   [uid, old_slug])
      else
        db.execute("UPDATE sports_follows SET value = ? WHERE user_id = ? AND kind = 'team' AND value = ?",
                   [new_slug, uid, old_slug])
      end
    end
  end

  puts "  #{old_slug} → #{new_slug}"
end

puts
puts 'Done.'
