module SudokuStore
  extend self

  # ── puzzles ───────────────────────────────────────────────────────────────

  def puzzle_for_date(date)
    db.execute('SELECT * FROM sudoku_puzzles WHERE puzzle_date = $1', [date.to_s]).first
  end

  def today_puzzle
    puzzle_for_date(Date.today)
  end

  # Generate and store today's puzzle if it doesn't exist yet.
  def ensure_today!
    return today_puzzle if today_puzzle

    clues, solution = SudokuGenerator.generate(difficulty: :medium)
    db.execute(
      'INSERT INTO sudoku_puzzles (puzzle_date, clues, solution, difficulty)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (puzzle_date) DO NOTHING',
      [Date.today.to_s, clues, solution, 'medium']
    )
    today_puzzle
  end

  # Pre-generate puzzles for the next N days (used by cron + seed script).
  def ensure_upcoming!(days: 7)
    days.times do |i|
      date = Date.today + i
      next if puzzle_for_date(date)

      clues, solution = SudokuGenerator.generate(difficulty: :medium)
      db.execute(
        'INSERT INTO sudoku_puzzles (puzzle_date, clues, solution, difficulty)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (puzzle_date) DO NOTHING',
        [date.to_s, clues, solution, 'medium']
      )
    end
  end

  # ── user state ────────────────────────────────────────────────────────────

  def state_for(user_id:, puzzle_id:)
    db.execute(
      'SELECT * FROM sudoku_states WHERE user_id = $1 AND puzzle_id = $2',
      [user_id, puzzle_id]
    ).first
  end

  # Upsert board state. board is an 81-char string; notes is a Hash.
  def save_state!(user_id:, puzzle_id:, board:, notes: {}, elapsed_secs: 0, completed: false)
    completed_sql = completed ? 'now()' : 'NULL'
    db.execute(
      "INSERT INTO sudoku_states (user_id, puzzle_id, board, notes, elapsed_secs, completed_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, #{completed_sql}, now())
       ON CONFLICT (user_id, puzzle_id) DO UPDATE
         SET board        = EXCLUDED.board,
             notes        = EXCLUDED.notes,
             elapsed_secs = EXCLUDED.elapsed_secs,
             completed_at = CASE
               WHEN sudoku_states.completed_at IS NOT NULL THEN sudoku_states.completed_at
               ELSE EXCLUDED.completed_at
             END,
             updated_at   = now()",
      [user_id, puzzle_id, board, notes.to_json, elapsed_secs]
    )
  end

  # Recent completions for the leaderboard strip (top 10 today).
  def completions_today(puzzle_id:)
    db.execute(
      'SELECT ss.elapsed_secs, ss.completed_at, u.username, u.display_name
       FROM sudoku_states ss
       JOIN users u ON u.id = ss.user_id
       WHERE ss.puzzle_id = $1 AND ss.completed_at IS NOT NULL
       ORDER BY ss.elapsed_secs ASC
       LIMIT 10',
      [puzzle_id]
    )
  end

  private

  def db
    Database.connection
  end
end
