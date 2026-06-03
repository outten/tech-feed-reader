require 'sidekiq'
require_relative '../games/trivia_generator'
require_relative '../games/trivia_store'
require_relative '../logger'

class GenerateTriviaWorker
  include Sidekiq::Worker

  sidekiq_options queue: :default, retry: 2

  def perform
    quiz = TriviaStore.ensure_today!
    if quiz
      AppLogger.info('generate_trivia_complete', quiz_id: quiz['id'])
    else
      AppLogger.warn('generate_trivia_skipped', reason: 'unavailable or failed')
    end
  end
end
