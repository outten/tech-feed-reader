#!/usr/bin/env ruby
# Pre-generate daily Sudoku puzzles for the next N days.
# Usage:
#   ruby scripts/generate_sudoku.rb          # generates next 7 days
#   DAYS=30 ruby scripts/generate_sudoku.rb  # generates next 30 days

require_relative '../app/database'
require_relative '../app/games/sudoku_generator'
require_relative '../app/games/sudoku_store'

Database.connect!
Database.migrate!

days = (ENV['DAYS'] || 7).to_i
puts "Generating Sudoku puzzles for the next #{days} days..."

days.times do |i|
  date = Date.today + i
  if SudokuStore.puzzle_for_date(date)
    puts "  #{date} — already exists, skipping"
    next
  end

  clues, solution = SudokuGenerator.generate(difficulty: :medium)
  Database.execute(
    'INSERT INTO sudoku_puzzles (puzzle_date, clues, solution, difficulty)
     VALUES ($1, $2, $3, $4) ON CONFLICT (puzzle_date) DO NOTHING',
    [date.to_s, clues, solution, 'medium']
  )
  puts "  #{date} — generated"
end

puts "Done."
