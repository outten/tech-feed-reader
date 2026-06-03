require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/games/sudoku_generator'
require_relative '../app/games/sudoku_store'

RSpec.describe 'Daily Sudoku' do
  include Rack::Test::Methods

  def app = TechFeedReader

  let(:user_id) do
    Database.connection.execute(
      "INSERT INTO users (username, display_name) VALUES ('sudoku_tester', 'Sudoku Tester')
       ON CONFLICT (username) DO UPDATE SET username = EXCLUDED.username
       RETURNING id", []
    ).first['id']
  end

  def signed_in(uid = user_id, &block)
    env = { 'rack.session' => { user_id: uid } }
    yield env
  end

  # ── SudokuGenerator ────────────────────────────────────────────────────────

  describe 'SudokuGenerator' do
    it 'returns an 81-char clues string and an 81-char solution string' do
      clues, solution = SudokuGenerator.generate
      expect(clues.length).to eq(81)
      expect(solution.length).to eq(81)
    end

    it 'solution contains only digits 1-9' do
      _, solution = SudokuGenerator.generate
      expect(solution).to match(/\A[1-9]{81}\z/)
    end

    it 'clues are a subset of the solution (non-blank cells match)' do
      clues, solution = SudokuGenerator.generate
      clues.chars.each_with_index do |c, i|
        next if c == '0'
        expect(c).to eq(solution[i])
      end
    end

    it 'leaves some cells blank (difficulty :medium removes ~46 cells)' do
      clues, _ = SudokuGenerator.generate(difficulty: :medium)
      blank_count = clues.count('0')
      expect(blank_count).to be_between(30, 60)
    end

    it 'generates a uniquely-solvable puzzle' do
      clues, solution = SudokuGenerator.generate(difficulty: :easy)
      grid = clues.chars.map(&:to_i)
      # build a simple backtracking counter capped at 2
      count = count_solutions(grid.dup, 0, 0)
      expect(count).to eq(1)
    end

    def count_solutions(grid, pos, count)
      while pos < 81 && grid[pos] != 0; pos += 1; end
      return count + 1 if pos == 81
      (1..9).each do |d|
        next unless valid?(grid, pos, d)
        grid[pos] = d
        count = count_solutions(grid, pos + 1, count)
        grid[pos] = 0
        return count if count >= 2
      end
      count
    end

    def valid?(grid, pos, d)
      r, c = pos / 9, pos % 9
      br, bc = (r / 3) * 3, (c / 3) * 3
      (0..8).none? { |i| grid[r * 9 + i] == d } &&
        (0..8).none? { |i| grid[i * 9 + c] == d } &&
        (0..2).none? { |dr| (0..2).any? { |dc| grid[(br + dr) * 9 + (bc + dc)] == d } }
    end
  end

  # ── SudokuStore ────────────────────────────────────────────────────────────

  describe 'SudokuStore' do
    let(:today) { Date.today }

    it 'ensure_today! creates a puzzle for today' do
      puzzle = SudokuStore.ensure_today!
      expect(puzzle).not_to be_nil
      expect(puzzle['puzzle_date'].to_s).to start_with(today.to_s)
      expect(puzzle['clues'].length).to eq(81)
      expect(puzzle['solution'].length).to eq(81)
    end

    it 'ensure_today! is idempotent' do
      p1 = SudokuStore.ensure_today!
      p2 = SudokuStore.ensure_today!
      expect(p1['id']).to eq(p2['id'])
    end

    it 'saves and retrieves user state' do
      puzzle = SudokuStore.ensure_today!
      board  = puzzle['solution'].gsub(/./, '0').ljust(81, '0')
      SudokuStore.save_state!(
        user_id: user_id, puzzle_id: puzzle['id'],
        board: board, elapsed_secs: 42
      )
      state = SudokuStore.state_for(user_id: user_id, puzzle_id: puzzle['id'])
      expect(state).not_to be_nil
      expect(state['elapsed_secs'].to_i).to eq(42)
    end

    it 'does not overwrite completed_at on subsequent saves' do
      puzzle = SudokuStore.ensure_today!
      SudokuStore.save_state!(
        user_id: user_id, puzzle_id: puzzle['id'],
        board: puzzle['solution'], elapsed_secs: 99, completed: true
      )
      SudokuStore.save_state!(
        user_id: user_id, puzzle_id: puzzle['id'],
        board: puzzle['solution'], elapsed_secs: 200, completed: false
      )
      state = SudokuStore.state_for(user_id: user_id, puzzle_id: puzzle['id'])
      expect(state['completed_at']).not_to be_nil
    end
  end

  # ── routes ─────────────────────────────────────────────────────────────────

  describe 'GET /games/sudoku' do
    it 'redirects to sign-in when not authenticated' do
      TechFeedReader.enforce_auth_wall = true
      get '/games/sudoku'
      expect(last_response.status).to eq(302)
      expect(last_response.location).to include('/sign-in')
    ensure
      TechFeedReader.enforce_auth_wall = false
    end

    it 'renders the sudoku page for a signed-in user' do
      signed_in { |env| get '/games/sudoku', {}, env }
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('sudoku-board')
      expect(last_response.body).to include('Daily Sudoku')
    end

    it 'embeds the puzzle clues and solution in data attributes' do
      signed_in { |env| get '/games/sudoku', {}, env }
      expect(last_response.body).to match(/data-clues="[0-9]{81}"/)
      expect(last_response.body).to match(/data-solution="[1-9]{81}"/)
    end
  end

  describe 'POST /games/sudoku/:id/state' do
    it 'saves state and returns ok: true' do
      puzzle = SudokuStore.ensure_today!
      payload = { board: '0' * 81, notes: {}, elapsed_secs: 10, completed: false }.to_json

      signed_in do |env|
        post "/games/sudoku/#{puzzle['id']}/state", payload,
             env.merge('CONTENT_TYPE' => 'application/json')
      end

      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)['ok']).to be true
    end
  end

  describe 'GET /games' do
    it 'renders the games index (not a redirect)' do
      signed_in { |env| get '/games', {}, env }
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('Daily Sudoku')
    end
  end
end
