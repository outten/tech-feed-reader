#!/usr/bin/env ruby
# One-shot migration runner. Reads db/migrations/*.sql and applies any
# whose version isn't already in schema_migrations. Idempotent.
#
# Invoked by `make migrate`. The web app also auto-migrates on boot
# (see app/main.rb) so this script is mainly for CI / setup / scripts
# that need the DB up before the web process starts.
require_relative '../app/database'

count = Database.migrate!
if count.zero?
  puts 'Schema is up to date — no migrations applied.'
else
  puts "Applied #{count} migration#{'s' unless count == 1}."
end
