require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/games/trivia_generator'
require_relative '../app/games/trivia_store'

RSpec.describe 'News Trivia' do
  include Rack::Test::Methods

  def app = TechFeedReader

  let(:user_id) do
    Database.connection.execute(
      "INSERT INTO users (username, display_name) VALUES ('trivia_tester', 'Trivia Tester')
       ON CONFLICT (username) DO UPDATE SET username = EXCLUDED.username
       RETURNING id", []
    ).first['id']
  end

  def signed_in(uid = user_id, &block)
    yield({ 'rack.session' => { user_id: uid } })
  end

  # Seed a quiz directly without calling Claude.
  def seed_quiz(date: Date.today)
    existing = TriviaStore.quiz_for_date(date)
    return existing if existing

    db = Database.connection
    quiz_id = db.execute(
      'INSERT INTO trivia_quizzes (quiz_date, llm_model) VALUES ($1, $2) RETURNING id',
      [date.to_s, 'test']
    ).first['id']

    5.times do |i|
      db.execute(
        'INSERT INTO trivia_questions
           (quiz_id, position, question, choice_a, choice_b, choice_c, choice_d,
            correct, explanation, article_title, article_url)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)',
        [quiz_id, i + 1, "Question #{i + 1}?",
         'Alpha', 'Beta', 'Gamma', 'Delta',
         'b', "Beta is correct because it is the second option.",
         "Test Article #{i + 1}", "https://example.com/#{i + 1}"]
      )
    end

    TriviaStore.quiz_for_date(date)
  end

  # ── TriviaGenerator ────────────────────────────────────────────────────────

  describe 'TriviaGenerator' do
    it 'returns :unavailable when ANTHROPIC_API_KEY is absent' do
      allow(TriviaGenerator).to receive(:available?).and_return(false)
      result = TriviaGenerator.generate(articles: [{ 'title' => 'Test', 'url' => 'http://x.com', 'content_text' => 'test' }])
      expect(result.status).to eq(:unavailable)
    end

    it 'returns :empty when no articles are supplied' do
      allow(TriviaGenerator).to receive(:available?).and_return(true)
      result = TriviaGenerator.generate(articles: [])
      expect(result.status).to eq(:empty)
    end

    describe 'parse_questions (private via send)' do
      it 'parses a well-formed JSON array' do
        raw = JSON.generate([
          { 'question' => 'Q?', 'a' => 'A', 'b' => 'B', 'c' => 'C', 'd' => 'D',
            'correct' => 'b', 'explanation' => 'B is right.',
            'article_title' => 'Title', 'article_url' => 'http://x.com' }
        ])
        questions = TriviaGenerator.send(:parse_questions, raw)
        expect(questions).to be_an(Array)
        expect(questions.first['correct']).to eq('b')
      end

      it 'strips markdown code fences before parsing' do
        raw = "```json\n[{\"question\":\"Q?\",\"a\":\"A\",\"b\":\"B\",\"c\":\"C\",\"d\":\"D\",\"correct\":\"a\",\"explanation\":\"E\",\"article_title\":\"T\",\"article_url\":\"U\"}]\n```"
        questions = TriviaGenerator.send(:parse_questions, raw)
        expect(questions).not_to be_nil
        expect(questions.length).to eq(1)
      end

      it 'returns nil for invalid JSON' do
        expect(TriviaGenerator.send(:parse_questions, 'not json')).to be_nil
      end

      it 'normalises correct letter to lowercase' do
        raw = JSON.generate([
          { 'question' => 'Q?', 'a' => 'A', 'b' => 'B', 'c' => 'C', 'd' => 'D',
            'correct' => 'C', 'explanation' => 'E', 'article_title' => 'T', 'article_url' => 'U' }
        ])
        q = TriviaGenerator.send(:parse_questions, raw).first
        expect(q['correct']).to eq('c')
      end

      it 'filters out entries with missing required keys' do
        raw = JSON.generate([
          { 'question' => 'Q?', 'a' => 'A' }  # missing b, c, d, correct, explanation
        ])
        expect(TriviaGenerator.send(:parse_questions, raw)).to be_empty
      end
    end
  end

  # ── TriviaStore ────────────────────────────────────────────────────────────

  describe 'TriviaStore' do
    it 'quiz_for_date returns nil when no quiz exists for a date' do
      future = Date.today + 365
      expect(TriviaStore.quiz_for_date(future)).to be_nil
    end

    it 'stores and retrieves questions' do
      quiz = seed_quiz
      questions = TriviaStore.questions_for(quiz['id'])
      expect(questions.length).to eq(5)
      expect(questions.first['position'].to_i).to eq(1)
    end

    it 'submit_answer! records the answer and returns correct flag' do
      quiz = seed_quiz
      q    = TriviaStore.questions_for(quiz['id']).first
      result = TriviaStore.submit_answer!(user_id: user_id, question_id: q['id'].to_i, answer: 'b')
      expect(result[:correct]).to be true
      expect(result[:correct_letter]).to eq('b')
    end

    it 'submit_answer! returns correct: false for a wrong answer' do
      quiz = seed_quiz
      q    = TriviaStore.questions_for(quiz['id']).first
      result = TriviaStore.submit_answer!(user_id: user_id, question_id: q['id'].to_i, answer: 'a')
      expect(result[:correct]).to be false
    end

    it 'submit_answer! is idempotent (ON CONFLICT DO NOTHING)' do
      quiz = seed_quiz
      q    = TriviaStore.questions_for(quiz['id']).first
      TriviaStore.submit_answer!(user_id: user_id, question_id: q['id'].to_i, answer: 'b')
      expect {
        TriviaStore.submit_answer!(user_id: user_id, question_id: q['id'].to_i, answer: 'a')
      }.not_to raise_error
    end

    it 'score_for counts correct answers' do
      quiz = seed_quiz
      qs   = TriviaStore.questions_for(quiz['id'])
      TriviaStore.submit_answer!(user_id: user_id, question_id: qs[0]['id'].to_i, answer: 'b')  # correct
      TriviaStore.submit_answer!(user_id: user_id, question_id: qs[1]['id'].to_i, answer: 'a')  # wrong
      score = TriviaStore.score_for(user_id: user_id, quiz_id: quiz['id'])
      expect(score[:total]).to eq(2)
      expect(score[:correct]).to eq(1)
    end

    it 'answers_for returns a hash keyed by question_id' do
      quiz = seed_quiz
      q    = TriviaStore.questions_for(quiz['id']).first
      TriviaStore.submit_answer!(user_id: user_id, question_id: q['id'].to_i, answer: 'b')
      answers = TriviaStore.answers_for(user_id: user_id, quiz_id: quiz['id'])
      expect(answers.keys).to include(q['id'].to_i)
    end
  end

  # ── routes ─────────────────────────────────────────────────────────────────

  describe 'GET /games/trivia' do
    context 'when no API key is set' do
      before { allow(TriviaGenerator).to receive(:available?).and_return(false) }

      it 'renders the unavailable state' do
        signed_in { |env| get '/games/trivia', {}, env }
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('API key')
      end
    end

    context 'with a pre-seeded quiz' do
      before { seed_quiz }

      it 'renders the quiz page with questions' do
        signed_in { |env| get '/games/trivia', {}, env }
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('Question 1')
        expect(last_response.body).to include('trivia-card')
      end

      it 'shows score badge' do
        signed_in { |env| get '/games/trivia', {}, env }
        expect(last_response.body).to include('trivia-score-badge')
      end
    end
  end

  describe 'POST /games/trivia/:question_id/answer' do
    before { seed_quiz }

    it 'accepts a valid answer and returns JSON with correct flag' do
      quiz = TriviaStore.today_quiz
      q    = TriviaStore.questions_for(quiz['id']).first

      signed_in do |env|
        post "/games/trivia/#{q['id']}/answer",
             { answer: 'b' }.to_json,
             env.merge('CONTENT_TYPE' => 'application/json')
      end

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body['correct']).to be true
      expect(body['correct_letter']).to eq('b')
      expect(body['explanation']).to be_a(String)
    end

    it 'returns 400 for an invalid answer letter' do
      quiz = TriviaStore.today_quiz
      q    = TriviaStore.questions_for(quiz['id']).first

      signed_in do |env|
        post "/games/trivia/#{q['id']}/answer",
             { answer: 'z' }.to_json,
             env.merge('CONTENT_TYPE' => 'application/json')
      end

      expect(last_response.status).to eq(400)
    end
  end

  describe 'GET /games' do
    it 'renders the games index with both tiles' do
      signed_in { |env| get '/games', {}, env }
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('Daily Sudoku')
      expect(last_response.body).to include('News Trivia')
    end
  end
end
