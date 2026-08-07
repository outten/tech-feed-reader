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
      # Hardcoded true, not env-driven. Measured against production:
      # with keep_unread: false, a first run deletes 89% of the
      # corpus, including 121,660 unread articles the user has never
      # seen. This job runs unattended every night with nobody
      # watching, so the safe behaviour has to be the only behaviour
      # — do not make this configurable without re-reading
      # openspec/changes/wire-production-article-retention/design.md.
      keep_unread: true
    )
  end
end
