module TriviaStore
  extend self

  QUESTIONS_PER_QUIZ = 5
  # Articles pulled from the last N hours to source questions.
  SOURCE_WINDOW_HOURS = 24
  # How many articles to send to Claude (enough variety, not too many tokens).
  SOURCE_ARTICLE_LIMIT = 20
  # Minimum content_text length to count as real trivia material. Guards
  # against feeds whose published_at sorts recent but whose content is
  # near-empty (e.g. a webcomic's caption text) crowding out genuine news.
  MIN_ARTICLE_CHARS = 100

  # ── quizzes ───────────────────────────────────────────────────────────────

  def quiz_for_date(date)
    db.execute('SELECT * FROM trivia_quizzes WHERE quiz_date = $1', [date.to_s]).first
  end

  def today_quiz
    quiz_for_date(Date.today)
  end

  # Generate and persist today's quiz.
  # force: true — delete any existing quiz for today and regenerate.
  # Returns the quiz row on success, nil if generation is unavailable/failed.
  def ensure_today!(force: false)
    if force
      existing = today_quiz
      if existing
        db.execute('DELETE FROM trivia_quizzes WHERE id = $1', [existing['id']])
      end
    else
      return today_quiz if today_quiz
    end

    return nil unless TriviaGenerator.available?

    articles = fetch_source_articles
    result   = TriviaGenerator.generate(articles: articles)
    return nil unless result.status == :ok

    store_quiz!(Date.today, result.questions, result.model)
    today_quiz
  end

  def questions_for(quiz_id)
    db.execute(
      'SELECT * FROM trivia_questions WHERE quiz_id = $1 ORDER BY position ASC',
      [quiz_id]
    )
  end

  # ── user answers ──────────────────────────────────────────────────────────

  # Returns a Hash of question_id → answer row for the given user + quiz.
  def answers_for(user_id:, quiz_id:)
    rows = db.execute(
      'SELECT ta.* FROM trivia_answers ta
       JOIN trivia_questions tq ON tq.id = ta.question_id
       WHERE ta.user_id = $1 AND tq.quiz_id = $2',
      [user_id, quiz_id]
    )
    rows.each_with_object({}) { |r, h| h[r['question_id'].to_i] = r }
  end

  # Record a user's answer. Returns { correct: bool, correct_letter: 'x', explanation: '...' }.
  def submit_answer!(user_id:, question_id:, answer:)
    q       = db.execute('SELECT * FROM trivia_questions WHERE id = $1', [question_id]).first
    return nil unless q

    correct = q['correct'] == answer.to_s.downcase
    db.execute(
      'INSERT INTO trivia_answers (user_id, question_id, answer, correct)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (user_id, question_id) DO NOTHING',
      [user_id, question_id, answer.to_s.downcase, correct]
    )
    { correct: correct, correct_letter: q['correct'], explanation: q['explanation'].to_s }
  end

  # Score summary for a user on a given quiz.
  def score_for(user_id:, quiz_id:)
    row = db.execute(
      'SELECT COUNT(*) AS total,
              SUM(CASE WHEN ta.correct THEN 1 ELSE 0 END) AS right_count
       FROM trivia_answers ta
       JOIN trivia_questions tq ON tq.id = ta.question_id
       WHERE ta.user_id = $1 AND tq.quiz_id = $2',
      [user_id, quiz_id]
    ).first
    { total: row['total'].to_i, correct: row['right_count'].to_i }
  end

  # Today's leaderboard — users who finished, sorted by score desc then time asc.
  def leaderboard_today(quiz_id:)
    db.execute(
      'SELECT u.username, u.display_name,
              COUNT(*) AS total,
              SUM(CASE WHEN ta.correct THEN 1 ELSE 0 END) AS right_count,
              MAX(ta.answered_at) AS finished_at
       FROM trivia_answers ta
       JOIN trivia_questions tq ON tq.id = ta.question_id
       JOIN users u ON u.id = ta.user_id
       WHERE tq.quiz_id = $1
       GROUP BY u.id, u.username, u.display_name
       HAVING COUNT(*) = $2
       ORDER BY right_count DESC, finished_at ASC
       LIMIT 10',
      [quiz_id, QUESTIONS_PER_QUIZ]
    )
  end

  # ── private ───────────────────────────────────────────────────────────────

  private

  def fetch_source_articles
    cutoff = (Time.now - SOURCE_WINDOW_HOURS * 3600).iso8601
    db.execute(
      'SELECT title, url, content_text FROM articles
       WHERE published_at > $1
         AND title IS NOT NULL
         AND content_text IS NOT NULL
         AND LENGTH(content_text) >= $2
       ORDER BY published_at DESC
       LIMIT $3',
      [cutoff, MIN_ARTICLE_CHARS, SOURCE_ARTICLE_LIMIT]
    )
  end

  def store_quiz!(date, questions, model)
    quiz_id = db.execute(
      'INSERT INTO trivia_quizzes (quiz_date, llm_model) VALUES ($1, $2) RETURNING id',
      [date.to_s, model]
    ).first['id']

    questions.first(QUESTIONS_PER_QUIZ).each_with_index do |q, i|
      db.execute(
        'INSERT INTO trivia_questions
           (quiz_id, position, question, choice_a, choice_b, choice_c, choice_d,
            correct, explanation, article_title, article_url)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)',
        [
          quiz_id, i + 1, q['question'],
          q['a'], q['b'], q['c'], q['d'],
          q['correct'], q['explanation'],
          q['article_title'].to_s, q['article_url'].to_s
        ]
      )
    end
  end

  def db
    Database.connection
  end
end
