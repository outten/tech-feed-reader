require_relative 'database'
require_relative 'summarizer/extractive'

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

    query = keywords.join(' OR ')
    Database.connection.execute(<<~SQL, [query, article['id'], user_id.to_i, limit])
      SELECT a.*, rank
      FROM articles a
      JOIN articles_fts f ON a.id = f.rowid
      WHERE articles_fts MATCH ?
        AND a.id != ?
        AND EXISTS (
          SELECT 1 FROM user_feed_subscriptions ufs
          WHERE ufs.user_id = ? AND ufs.feed_id = a.feed_id
        )
      ORDER BY rank
      LIMIT ?
    SQL
  rescue SQLite3::SQLException
    # FTS5 can reject synthesized queries on rare token shapes — fall
    # back to no recommendations rather than erroring the article view.
    []
  end

  # Top-N most frequent non-stopword tokens, ordered by frequency
  # descending. Stopword list is shared with the extractive summarizer.
  def top_keywords(text, limit: TARGET_KEYWORDS)
    tokens = text
      .downcase
      .scan(/[a-z][a-z'-]{#{MIN_TOKEN_LEN - 1},}/)
      .reject { |t| Summarizer::Extractive::STOPWORDS.include?(t) }

    tokens.tally.sort_by { |_, c| -c }.first(limit).map(&:first)
  end
end
