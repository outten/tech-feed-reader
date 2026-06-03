#!/usr/bin/env ruby
# Generate today's News Trivia quiz from the last 24h of articles.
# Usage:
#   ruby scripts/generate_trivia.rb        # generate (skips if exists)
#   FORCE=1 ruby scripts/generate_trivia.rb  # delete + regenerate today's quiz
# Requires ANTHROPIC_API_KEY in the environment.

require_relative '../app/credentials'
require_relative '../app/database'
require_relative '../app/logger'
require_relative '../app/games/trivia_generator'
require_relative '../app/games/trivia_store'

Database.migrate!

force = ENV['FORCE'] == '1'

unless TriviaGenerator.available?
  puts "ANTHROPIC_API_KEY is not set. Cannot generate quiz."
  exit 1
end

puts "Generating today's News Trivia quiz#{force ? ' (force)' : ''}..."
quiz = TriviaStore.ensure_today!(force: force)

if quiz
  puts "Done — quiz id=#{quiz['id']}"
else
  puts "Generation failed. Check logs for details."
  exit 1
end
