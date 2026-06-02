-- Daily Sudoku puzzles (one per day, shared across all users)
CREATE TABLE IF NOT EXISTS sudoku_puzzles (
  id           BIGSERIAL    PRIMARY KEY,
  puzzle_date  DATE         NOT NULL UNIQUE,
  clues        CHAR(81)     NOT NULL,  -- '0' = blank, '1'-'9' = given digit
  solution     CHAR(81)     NOT NULL,
  difficulty   VARCHAR(10)  NOT NULL DEFAULT 'medium',
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Per-user puzzle progress
CREATE TABLE IF NOT EXISTS sudoku_states (
  id           BIGSERIAL    PRIMARY KEY,
  user_id      BIGINT       NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  puzzle_id    BIGINT       NOT NULL REFERENCES sudoku_puzzles(id) ON DELETE CASCADE,
  board        CHAR(81)     NOT NULL,  -- current board state (includes user fills)
  notes        JSONB        NOT NULL DEFAULT '{}',  -- pencil marks: {"12": [1,3,5], ...}
  completed_at TIMESTAMPTZ,
  elapsed_secs INTEGER      NOT NULL DEFAULT 0,
  updated_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
  UNIQUE(user_id, puzzle_id)
);
