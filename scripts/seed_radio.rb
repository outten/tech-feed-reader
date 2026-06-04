#!/usr/bin/env ruby
# Seed the radio_stations catalog into the database.
# Safe to re-run — uses ON CONFLICT DO UPDATE so existing rows are refreshed.

require_relative '../app/credentials'
require_relative '../app/database'
require_relative '../app/radio_catalog'
require_relative '../app/radio_store'

Database.migrate!

puts "Seeding #{RadioCatalog::STATIONS.length} radio stations..."
RadioStore.seed_catalog!
puts "Done. #{RadioStore.all_stations.length} stations in DB."
