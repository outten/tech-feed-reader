require 'sidekiq'
require_relative '../games/trivia_generator'
require_relative '../games/trivia_store'
require_relative '../logger'
require_relative '../notifier'

class GenerateTriviaWorker
  include Sidekiq::Worker

  sidekiq_options queue: :default, retry: 2

  # force=true regenerates today's quiz even if one already exists.
  # Trigger from Sidekiq UI by passing argument: true
  def perform(force = false)
    quiz = TriviaStore.ensure_today!(force: force)
    if quiz
      AppLogger.info('generate_trivia_complete', quiz_id: quiz['id'], force: force)
    else
      AppLogger.warn('generate_trivia_skipped', reason: 'unavailable or failed')
      Notifier.push(
        title:      'Feeder: trivia quiz not generated',
        body:       "GenerateTriviaWorker ran but no quiz was produced (unavailable or failed, force=#{force})",
        tags:       %w[warning],
        priority:   'high',
        dedupe_key: 'trivia_generation_skipped'
      )
    end
  end
end
