require 'sidekiq'
require 'time'
require_relative '../recommendation/for_you'
require_relative '../users_store'
require_relative '../logger'

# Pre-warms the For-You ranking cache for recently-active users so the home
# page, /articles?sort=relevance, and the deferred Read-next fragment hit a
# warm cache instead of paying the cold compute_ranking (which can take
# seconds on a cold Postgres buffer pool). See change: speed-up-article-load.
#
# Runs on a cron cadence shorter than RANKING_TTL (5 min) so an active user's
# cache never lapses. Bounded to users seen in the last ACTIVE_WINDOW_HOURS so
# the work scales with *active* users, not the whole table; processed
# sequentially in one job (one DB connection) to respect the small managed-PG
# connection budget.
class ForYouCacheWarmWorker
  include Sidekiq::Worker

  sidekiq_options queue: :default, retry: 1

  ACTIVE_WINDOW_HOURS = 24

  # The (state, kind, topic) variants the hot pages request: :unread drives
  # next_after + the home For-You feed; :all drives /articles?sort=relevance.
  WARM_STATES = %i[unread all].freeze

  def perform
    cutoff   = (Time.now.utc - ACTIVE_WINDOW_HOURS * 3600).strftime('%Y-%m-%d %H:%M:%S')
    user_ids = UsersStore.active_since(cutoff)
    now      = Time.now.utc

    user_ids.each do |uid|
      WARM_STATES.each do |state|
        Recommendation::ForYou.ranked_ids(uid, state: state, kind: :all, topic: nil, now: now, force: true)
      end
    end

    AppLogger.info('foryou_cache_warm', users: user_ids.length, states: WARM_STATES.length)
  end
end
