require 'date'
require 'json'
require_relative 'database'
require_relative 'recommendation'
require_relative 'stopwords'
require_relative 'cache'

# "Trending topics" widget data — pure-Ruby term-frequency clustering
# over recent articles, no graph algorithms required. Per SPEC.md
# milestone M: deterministic, cheap, no external libs.
#
# Algorithm (STUFF #28):
#   1. Pull articles published in the last `days` window (capped at
#      RECENT_LIMIT so a thousand-article corpus doesn't tokenize into
#      memory on every dashboard render).
#   2. For each article, collect weighted signal terms from two sources:
#        a. Publisher-supplied category tags from articles.categories
#           (#28.2) — weight CATEGORY_WEIGHT. The publisher's own
#           taxonomy is a stronger signal than tokens extracted from
#           the body, so categories nudge their terms up.
#        b. Top KEYWORDS_PER_ARTICLE distinctive body tokens via
#           Recommendation.top_keywords (#28.1 — shared tokenizer that
#           strips URLs + a expanded stopword list) — weight 1.0.
#   3. Build term → [(article, weight), ...]. A term hit by both a
#      category and a keyword on the same article uses the higher of
#      the two weights (no double-count for a single article).
#   4. Score each term as the sum of contributing weights. `count` is
#      the distinct article count.
#   5. Drop terms below `min_articles` distinct-article count.
#   6. Drop terms whose distinct-article count exceeds UBIQUITY_RATIO
#      of the corpus (#28.3 — anti-noise ceiling: in a 500-article
#      window, anything appearing in >250 articles is a brand tag /
#      site boilerplate, not a topic). Skipped on tiny corpora where
#      the math is meaningless.
#   7. Sort by score desc, term asc; return top `limit`.
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

  CATEGORY_WEIGHT       = 2.0   # publisher tags are stronger signal than body keywords
  PHRASE_WEIGHT         = 1.5   # adjacent-capitalized phrases ("Jannik Sinner") beat unigrams
  PHRASES_PER_ARTICLE   = 3
  UBIQUITY_RATIO        = 0.5   # drop terms appearing in >50% of the corpus
  UBIQUITY_MIN_CORPUS   = 20    # below this corpus size the ratio is meaningless

  # Brand-noise filter for categories lives in app/stopwords.rb
  # (Stopwords::CATEGORY) along with the other two stopword lists.

  module_function

  # Returns array of clusters in score-desc order:
  #   [{ term:, count:, articles: [{uid, title, ...}, ...] }, ...]
  # `count` is the distinct-article count so the view can render
  # "N articles" directly; `score` is the weighted sum (categories
  # contribute CATEGORY_WEIGHT, keywords contribute 1.0).
  # Articles are the 3 most recent of each cluster.
  # Cached wrapper. The clustering is cross-corpus (not per-user) and
  # changes slowly, so cache it for 30 min — this is the heaviest query
  # on /admin/dashboard and /topics (scans + tokenizes up to RECENT_LIMIT
  # rows). Marshal: the result mixes symbol keys (term:/count:/articles:)
  # with string-keyed article rows, which JSON can't round-trip.
  def recent(days: WINDOW_DAYS_DEFAULT, min_articles: MIN_ARTICLES_DEFAULT, limit: TOP_TOPICS_DEFAULT)
    Cache.fetch("topics:v1:#{days}:#{min_articles}:#{limit}", ttl: 1800, marshal: true) do
      compute_recent(days: days, min_articles: min_articles, limit: limit)
    end
  end

  def compute_recent(days: WINDOW_DAYS_DEFAULT, min_articles: MIN_ARTICLES_DEFAULT, limit: TOP_TOPICS_DEFAULT)
    cutoff = (Date.today - days + 1).to_s
    date_expr = Database.date_sql('published_at')
    rows = Database.connection.execute(<<~SQL, [cutoff, RECENT_LIMIT])
      SELECT id, uid, title, content_text, feed_id, published_at, categories
      FROM articles
      WHERE #{date_expr} >= ?
      ORDER BY published_at DESC
      LIMIT ?
    SQL
    return [] if rows.empty?

    total = rows.length
    # term → { article_id => [article, weight] } so an article that
    # surfaces a term via both its category and its body keywords
    # registers once at the higher weight.
    term_to_hits = Hash.new { |h, k| h[k] = {} }

    rows.each do |article|
      weighted_terms_for(article).each do |term, weight|
        existing = term_to_hits[term][article['id']]
        term_to_hits[term][article['id']] = [article, [existing&.last || 0.0, weight].max]
      end
    end

    ceiling_active = total >= UBIQUITY_MIN_CORPUS
    ceiling_count  = (total * UBIQUITY_RATIO).to_i

    term_to_hits
      .each_pair
      .filter_map do |term, hits|
        count = hits.length
        next if count < min_articles
        next if ceiling_active && count > ceiling_count
        score    = hits.values.sum { |(_, w)| w }
        articles = hits.values.map(&:first).first(3)
        { term: term, count: count, score: score, articles: articles }
      end
      .sort_by { |c| [-c[:score], c[:term]] }
      .first(limit)
  end

  class << self
    private

    # Weighted signal terms for one article — yields [term, weight]
    # pairs. Caller dedupes per-article. Three signal sources:
    #   * Publisher categories (CATEGORY_WEIGHT = 2.0)
    #   * Proper-noun phrases ("Jannik Sinner" — PHRASE_WEIGHT = 1.5;
    #     STUFF #28.4 — keeps named entities from splitting into
    #     competing single-word clusters)
    #   * Top body keywords (weight 1.0). Single words that are
    #     components of a phrase emitted on the same article get
    #     suppressed here so the unigram clusters don't duplicate the
    #     phrase cluster (one "jannik sinner" cluster, no "jannik" and
    #     "sinner" siblings).
    def weighted_terms_for(article)
      pairs = []
      parse_categories(article['categories']).each { |t| pairs << [t, CATEGORY_WEIGHT] }

      text    = article['content_text'].to_s
      phrases = Recommendation.top_phrases(text, limit: PHRASES_PER_ARTICLE)
      phrases.each { |p| pairs << [p, PHRASE_WEIGHT] }

      phrase_components = phrases.flat_map { |p| p.split(/\s+/) }.to_set
      Recommendation.top_keywords(text, limit: KEYWORDS_PER_ARTICLE).each do |t|
        next if phrase_components.include?(t)
        pairs << [t, 1.0]
      end
      pairs
    end

    def parse_categories(raw)
      return [] if raw.nil? || raw.empty?
      JSON.parse(raw)
        .flat_map { |c| c.to_s.downcase.scan(/[a-z][a-z'-]{2,}/) }
        .reject { |t| Stopwords::CATEGORY.include?(t) || Stopwords::GENERAL.include?(t) }
        .uniq
    rescue JSON::ParserError
      []
    end
  end
end
