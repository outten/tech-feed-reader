#!/usr/bin/env ruby
# Generate today's News Trivia quiz from the last 24h of articles.
# Usage: ruby scripts/generate_trivia.rb
# Requires ANTHROPIC_API_KEY in the environment.

require_relative '../app/database'
require_relative '../app/logger'
require_relative '../app/games/trivia_generator'
require_relative '../app/games/trivia_store'

Database.connect! rescue nil
Database.migrate!

if TriviaStore.today_quiz
  puts "Today's trivia quiz already exists (id=#{TriviaStore.today_quiz['id']}). Nothing to do."
  exit 0
end

unless TriviaGenerator.available?
  puts "ANTHROPIC_API_KEY is not set. Cannot generate quiz."
  exit 1
end

puts "Generating today's News Trivia quiz..."
quiz = TriviaStore.ensure_today!

if quiz
  puts "Done — quiz id=#{quiz['id']}"
else
  puts "Generation failed. Check logs for details."
  exit 1
end
