#!/usr/bin/env ruby
# Pre-generate daily Sudoku puzzles for the next N days.
# Usage:
#   ruby scripts/generate_sudoku.rb          # generates next 7 days
#   DAYS=30 ruby scripts/generate_sudoku.rb  # generates next 30 days

require_relative '../app/credentials'
require_relative '../app/database'
require_relative '../app/logger'
require_relative '../app/games/sudoku_generator'
require_relative '../app/games/sudoku_store'

Database.migrate!

days = (ENV['DAYS'] || 7).to_i
puts "Generating Sudoku puzzles for the next #{days} days..."

SudokuStore.ensure_upcoming!(days: days)

puts "Done."
