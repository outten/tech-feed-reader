#!/usr/bin/env ruby
# Dev helper — insert a user row (no passkey, no recovery codes).
# Useful when you've blown away the DB and want a known user_id=1
# to inherit the existing single-user data without going through the
# full WebAuthn ceremony.
#
# Usage:
#   make seed-user USER=todd
#   bundle exec ruby scripts/seed_user.rb todd "Todd Outten"
#
# WARNING: a user inserted this way has no credentials — you can't
# sign in as them via /sign-in until you also register a passkey
# through the web UI. For local dev only.

require_relative '../app/credentials'
require_relative '../app/database'
require_relative '../app/users_store'

username     = ARGV[0] || 'todd'
display_name = ARGV[1]

Database.migrate!

begin
  user = UsersStore.create(username: username, display_name: display_name)
  puts "Seeded user id=#{user['id']} username=#{user['username']} display_name=#{user['display_name']}"
  puts ''
  puts 'NOTE: this user has no passkey. To sign in:'
  puts "  1. Visit /sign-up in a browser"
  puts "  2. Enter username '#{user['username']}' — registration will fail (taken)"
  puts "  TODO: add a /account/passkeys/add flow in a follow-up so existing users can register"
  puts "        without re-creating their account. For now, blow away the row + re-sign up."
rescue UsersStore::InvalidUsername => e
  warn "Invalid username: #{e.message}"
  exit 1
rescue SQLite3::ConstraintException
  warn "Username '#{username}' already taken."
  exit 1
end
