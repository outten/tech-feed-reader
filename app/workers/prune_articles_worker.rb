require 'sidekiq'
require_relative '../pruner'
require_relative '../logger'

# Daily Sidekiq-cron job: enforce the article retention policy in
# production. Pruner.prune_old already existed but was previously only
# invoked from scripts/refresh_feeds.rb (the make refresh-feeds / make
# scheduler CLI path) or `make prune`, neither of which production's
# docker-compose stack runs — so retention never actually happened
# there. See openspec/changes/wire-production-article-retention.
class PruneArticlesWorker
  include Sidekiq::Worker

  sidekiq_options queue: :default, retry: 2

  # Pruner.prune_old already logs a structured 'prune_articles' event
  # with the deleted/kept counts, so perform doesn't log again.
  def perform
    Pruner.prune_old(
      retention_days: Pruner.effective_retention_days,
      # keep_unread: false — deliberate, not the default it shipped
      # with. The first-ever run needed keep_unread: true (unread
      # articles exempt forever) because the growth rate against the
      # existing 138K-row backlog was unknown. Once shipped, real data
      # showed ~2,000 articles/day ingested with almost no read-through,
      # putting the unread backlog on an unbounded growth path (~9GB/yr
      # projected). RETENTION_DAYS was raised 7 -> 30 in the same change
      # so unread articles now get a full month before expiring, same as
      # read ones — a bounded reading window instead of no window at
      # all. See openspec/changes/wire-production-article-retention
      # design.md's "Decision 2 (revised)" for the full numbers.
      keep_unread: false
    )
  end
end
