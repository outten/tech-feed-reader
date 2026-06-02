require 'sidekiq'
require_relative '../games/sudoku_generator'
require_relative '../games/sudoku_store'
require_relative '../logger'

class GenerateSudokuWorker
  include Sidekiq::Worker

  sidekiq_options queue: :default, retry: 2

  def perform
    SudokuStore.ensure_upcoming!(days: 7)
    AppLogger.info('generate_sudoku_complete', days: 7)
  end
end
