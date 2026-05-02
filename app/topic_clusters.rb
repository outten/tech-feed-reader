require 'date'
require_relative 'database'
require_relative 'recommendation'

# "Trending topics" widget data — pure-Ruby term-frequency clustering
# over recent articles, no graph algorithms required. Per SPEC.md
# milestone M: deterministic, cheap, no external libs.
#
# Algorithm:
#   1. Pull articles published in the last `days` window (capped at
#      RECENT_LIMIT so a thousand-article corpus doesn't tokenize into
#      memory on every dashboard render).
#   2. For each article, take its top KEYWORDS_PER_ARTICLE distinctive
#      tokens via Recommendation.top_keywords (shared stopword list +
#      tokenizer with the rest of the app).
#   3. Invert into a term → [article, ...] index.
#   4. Keep only terms with at least `min_articles` hits, sort by hit
#      count desc, take the top `limit`.
#
# An article appears in multiple topics when its top-5 distinctive
# terms span multiple themes — an "AI safety news" piece will land in
# both the "ai" and "safety" clusters. That's the correct read: the
# point is to surface what people are talking about, not to assign
# each article to a single bucket.
module TopicClusters
  RECENT_LIMIT          = 500   # cap rows pulled per render
  KEYWORDS_PER_ARTICLE  = 5
  MIN_ARTICLES_DEFAULT  = 3
  WINDOW_DAYS_DEFAULT   = 14
  TOP_TOPICS_DEFAULT    = 8

  module_function

  # Returns array of clusters in count-desc order:
  #   [{ term:, count:, articles: [{uid, title, ...}, ...] }, ...]
  # Articles are the 3 most recent of each cluster, suitable for
  # rendering as inline links under the topic.
  def recent(days: WINDOW_DAYS_DEFAULT, min_articles: MIN_ARTICLES_DEFAULT, limit: TOP_TOPICS_DEFAULT)
    cutoff = (Date.today - days + 1).to_s
    rows = Database.connection.execute(<<~SQL, [cutoff, RECENT_LIMIT])
      SELECT id, uid, title, content_text, feed_id, published_at
      FROM articles
      WHERE DATE(published_at) >= ?
      ORDER BY published_at DESC
      LIMIT ?
    SQL
    return [] if rows.empty?

    term_to_articles = Hash.new { |h, k| h[k] = [] }
    rows.each do |article|
      keywords = Recommendation.top_keywords(article['content_text'].to_s, limit: KEYWORDS_PER_ARTICLE)
      keywords.each { |kw| term_to_articles[kw] << article }
    end

    term_to_articles
      .each_pair
      .filter_map do |term, articles|
        next if articles.length < min_articles
        { term: term, count: articles.length, articles: articles.first(3) }
      end
      .sort_by { |c| [-c[:count], c[:term]] }
      .first(limit)
  end
end
