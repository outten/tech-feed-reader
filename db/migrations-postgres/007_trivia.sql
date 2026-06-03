-- Daily news trivia quiz (one per day, shared across all users)
CREATE TABLE IF NOT EXISTS trivia_quizzes (
  id          BIGSERIAL    PRIMARY KEY,
  quiz_date   DATE         NOT NULL UNIQUE,
  llm_model   VARCHAR(80),
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- 5 questions per quiz
CREATE TABLE IF NOT EXISTS trivia_questions (
  id            BIGSERIAL    PRIMARY KEY,
  quiz_id       BIGINT       NOT NULL REFERENCES trivia_quizzes(id) ON DELETE CASCADE,
  position      SMALLINT     NOT NULL,  -- display order (1-5)
  question      TEXT         NOT NULL,
  choice_a      TEXT         NOT NULL,
  choice_b      TEXT         NOT NULL,
  choice_c      TEXT         NOT NULL,
  choice_d      TEXT         NOT NULL,
  correct       CHAR(1)      NOT NULL CHECK (correct IN ('a','b','c','d')),
  explanation   TEXT,
  article_title TEXT,
  article_url   TEXT
);

-- Per-user answer tracking
CREATE TABLE IF NOT EXISTS trivia_answers (
  id          BIGSERIAL    PRIMARY KEY,
  user_id     BIGINT       NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  question_id BIGINT       NOT NULL REFERENCES trivia_questions(id) ON DELETE CASCADE,
  answer      CHAR(1)      NOT NULL CHECK (answer IN ('a','b','c','d')),
  correct     BOOLEAN      NOT NULL,
  answered_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
  UNIQUE(user_id, question_id)
);
