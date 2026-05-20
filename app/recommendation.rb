require_relative 'database'
require_relative 'summarizer/extractive'
require_relative 'stopwords'

# "Articles like this" — deterministic, term-overlap based, no
# personalization. Validates against SPEC.md's "no recommendation
# engine" non-goal: this is content-similarity surfacing, not a
# tracking-driven feed.
#
# Strategy: pick the most distinctive non-stopword tokens from the
# target article, run them as an OR'd FTS5 MATCH against
# articles_fts, exclude the target itself, return the top-N by FTS5's
# built-in `rank` (BM25). This reuses the FTS5 index we already
# maintain on every insert (no extra storage, no per-render scan of
# the corpus, scales to thousands of articles).
#
# Falls back to [] if the article has too little content to extract
# keywords from, or if FTS5 errors on the synthesized query.
module Recommendation
  TARGET_KEYWORDS = 8     # how many top-frequency tokens to use as the MATCH query
  MIN_TOKEN_LEN   = 3     # ignore 1- and 2-char tokens; mostly noise
  DEFAULT_LIMIT   = 5

  module_function

  # Returns rows shaped like ArticlesStore.recent (with the FTS5 `rank`
  # column added). Empty array when there's nothing to compare against.
  def for_article(user_id, article, limit: DEFAULT_LIMIT)
    return [] if article.nil?

    keywords = top_keywords(article['content_text'].to_s)
    return [] if keywords.empty?

    # websearch_to_tsquery understands `OR` and is gentler than plain
    # to_tsquery on unusual tokens (won't error on stray punctuation).
    query = keywords.join(' OR ')
    Database.connection.execute(<<~SQL, [query, query, article['id'], user_id.to_i, limit])
      SELECT a.*, ts_rank(a.tsv, websearch_to_tsquery('english', ?)) AS rank
      FROM articles a
      WHERE a.tsv @@ websearch_to_tsquery('english', ?)
        AND a.id != ?
        AND EXISTS (
          SELECT 1 FROM user_feed_subscriptions ufs
          WHERE ufs.user_id = ? AND ufs.feed_id = a.feed_id
        )
      ORDER BY rank DESC
      LIMIT ?
    SQL
  rescue PG::Error
    # tsquery can reject synthesized queries on rare token shapes —
    # fall back to no recommendations rather than erroring the
    # article view.
    []
  end

  # STUFF #28 — strip URLs, emails, and bare hostnames before
  # tokenization so fragments like `com`, `https`, `www` don't leak in
  # as standalone tokens. content_text is the post-loofah plaintext —
  # `<a>` markup is gone, but bare URLs that appeared as body text stay.
  URL_RX   = %r{https?://\S+}i
  EMAIL_RX = /\S+@\S+\.\S+/
  HOST_RX  = %r{\b[a-z0-9-]+(?:\.[a-z0-9-]+)+(?:/\S*)?}i

  # STUFF #28.4 — proper-noun phrase pattern: exactly 2 adjacent
  # capitalized words (e.g. "Jannik Sinner", "New York"). A single
  # capitalized word at sentence-start is too ambiguous to use as a
  # signal, so we require pairs minimum. Bigram-only (not trigram) so
  # repeated phrases like "Jannik Sinner Jannik Sinner" stay countable
  # via String#scan's non-overlapping advance: a `{1,2}` trailing-word
  # quantifier would greedily consume three words and corrupt the
  # frequency tally on tightly-packed mentions. Trigrams like
  # "New York City" cluster as "new york" — acceptable trade.
  PHRASE_RX = /\b[A-Z][a-z'À-ſ]+\s+[A-Z][a-z'À-ſ]+\b/

  # Stopword sets (STUFF #28.5) — three lists live in app/stopwords.rb:
  #   * Stopwords::GENERAL  — single-word topic + summary filter
  #   * Stopwords::PHRASE   — phrase-rejection (articles, pronouns)
  #   * Stopwords::CATEGORY — publisher-category brand noise
  # Recommendation uses GENERAL for top_keywords and PHRASE for top_phrases.

  def strip_noise(text)
    text.to_s.gsub(URL_RX, ' ').gsub(EMAIL_RX, ' ').gsub(HOST_RX, ' ')
  end

  # Top-N most frequent non-stopword tokens, ordered by frequency
  # descending. Stopword list is shared with the extractive summarizer.
  def top_keywords(text, limit: TARGET_KEYWORDS)
    tokens = strip_noise(text)
      .downcase
      .scan(/[a-z][a-z'-]{#{MIN_TOKEN_LEN - 1},}/)
      .reject { |t| Stopwords::GENERAL.include?(t) }

    tokens.tally.sort_by { |_, c| -c }.first(limit).map(&:first)
  end

  # STUFF #28.4 — top-N proper-noun phrases, frequency-ordered.
  # Phrases are returned as lowercase, space-joined strings ("jannik
  # sinner") so callers can split on space to reach the component
  # tokens. Filters out phrases where any component is a stopword
  # (kills "The President" / "I Said" leakage from sentence-initial
  # capitals). Used by TopicClusters to keep "Jannik Sinner" as one
  # cluster rather than two competing single-word clusters.
  def top_phrases(text, limit: TARGET_KEYWORDS)
    candidates = strip_noise(text).scan(PHRASE_RX).map(&:downcase)
    candidates.reject! do |phrase|
      phrase.split(/\s+/).any? { |w| Stopwords::PHRASE.include?(w) }
    end
    candidates.tally.sort_by { |_, c| -c }.first(limit).map(&:first)
  end
end
