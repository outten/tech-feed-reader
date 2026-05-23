require 'sidekiq'
require_relative '../article_link_scrubber'
require_relative '../logger'

# STUFF #61 — daily Sidekiq-cron job: scrub any article content_html
# that's still flagged content_scrubbed = FALSE. Catches articles
# imported through a code path that bypassed feed_parser.rb's
# Sanitizer.sanitize_html(base_url:) call (e.g. future bulk-import
# tools, manual SQL inserts, or a regression where someone forgets
# to thread the base_url through).
#
# Steady state: nothing to do; the work runs in milliseconds. The
# WHERE-clause filter on content_scrubbed = FALSE makes the query
# cheap regardless of total article count.
class FixArticleLinksWorker
  include Sidekiq::Worker

  # Capped retries — the work is idempotent so retries are safe, but
  # we don't want a transient DB blip to pile up 25 attempts over
  # 21 days (the default) when the next daily tick is coming.
  sidekiq_options queue: :default, retry: 2

  def perform
    result = ArticleLinkScrubber.run!(logger: AppLogger)
    AppLogger.info('fix_article_links_complete', **result)
  end
end
