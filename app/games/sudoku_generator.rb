module SudokuGenerator
  DIGITS = (1..9).to_a

  # Returns [clues_string, solution_string], both 81-char strings.
  # '0' = blank cell, '1'-'9' = given digit.
  def self.generate(difficulty: :medium)
    solution = build_complete_grid
    clues    = remove_cells(solution.dup, difficulty)
    [clues.join, solution.join]
  end

  # ── private helpers ──────────────────────────────────────────────────────

  def self.build_complete_grid
    grid = Array.new(81, 0)
    fill!(grid, 0)
    grid
  end
  private_class_method :build_complete_grid

  def self.fill!(grid, pos)
    return true if pos == 81
    return fill!(grid, pos + 1) if grid[pos] != 0

    DIGITS.shuffle.each do |d|
      if valid?(grid, pos, d)
        grid[pos] = d
        return true if fill!(grid, pos + 1)
        grid[pos] = 0
      end
    end
    false
  end
  private_class_method :fill!

  def self.valid?(grid, pos, digit)
    r, c  = pos / 9, pos % 9
    br, bc = (r / 3) * 3, (c / 3) * 3

    (0..8).each { |i| return false if grid[r * 9 + i] == digit }   # row
    (0..8).each { |i| return false if grid[i * 9 + c] == digit }   # col
    (0..2).each do |dr|
      (0..2).each do |dc|
        return false if grid[(br + dr) * 9 + (bc + dc)] == digit   # box
      end
    end
    true
  end
  private_class_method :valid?

  CELLS_TO_REMOVE = { easy: 36, medium: 46, hard: 54 }.freeze

  def self.remove_cells(grid, difficulty)
    target  = CELLS_TO_REMOVE.fetch(difficulty, 46)
    removed = 0

    (0..80).to_a.shuffle.each do |pos|
      break if removed >= target
      saved       = grid[pos]
      grid[pos]   = 0
      if unique_solution?(grid)
        removed += 1
      else
        grid[pos] = saved   # put it back
      end
    end
    grid
  end
  private_class_method :remove_cells

  # Returns true iff the puzzle has exactly one solution (stops at 2).
  def self.unique_solution?(grid)
    count_solutions(grid.dup, 0, 0) == 1
  end
  private_class_method :unique_solution?

  def self.count_solutions(grid, pos, count)
    while pos < 81 && grid[pos] != 0
      pos += 1
    end
    return count + 1 if pos == 81

    DIGITS.each do |d|
      next unless valid?(grid, pos, d)
      grid[pos] = d
      count = count_solutions(grid, pos + 1, count)
      grid[pos] = 0
      return count if count >= 2
    end
    count
  end
  private_class_method :count_solutions
end
