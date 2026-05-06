require_relative '../database'
require_relative '../recommendation'
require_relative '../feed_feedback_store'

# Phase 6 — personalised "For You" ranker.
#
# Replaces the chronological sort on /articles?sort=relevance with a
# blended score:
#
#   score = recency_decay(published_at)
#         × per_feed_weight                        (Phase 3, clamped 0.25..3.0)
#         × (1 + α × positive_overlap)             (positive corpus boost)
#         × max(NEGATIVE_FLOOR, 1 − β × negative_overlap)   (negative damp, never zero)
#
# **Empty-corpus / default-weight case** collapses cleanly to
# `recency × 1.0 × 1.0 × 1.0` ⇒ pure chronological. So a brand-new
# install ranks the same as today; the more the user feeds back, the
# more the ranking diverges from chronological.
#
# **Corpus selection** — cheap, no background job:
#   positive = bookmarked + feedback=+1 + passive_feedback=+1
#   negative = feedback=-1 + passive_feedback=-1 + archived-without-reading
#
# Each capped to CORPUS_LIMIT recent rows. From those rows we extract
# the top TOP_TERMS distinctive tokens (Recommendation.top_keywords
# handles the stopword strip + frequency tally).
#
# **Overlap = simple set intersection** between the candidate's title
# tokens and the corpus term set, saturating at OVERLAP_SAT matches
# (more matches don't keep boosting forever — keeps the score bounded).
# Tokenizing titles only, not full bodies, keeps the ranker fast on a
# 500-row candidate window: titles average ~60 chars vs. content_text
# averaging ~5 KB.
module Recommendation
  module ForYou
    HALF_LIFE_HOURS  = 48      # recency decay
    POSITIVE_BOOST   = 0.5     # α
    NEGATIVE_DAMP    = 0.5     # β
    NEGATIVE_FLOOR   = 0.4     # hard cap on demotion: a single 👎 can't hide a topic
    CORPUS_LIMIT     = 50      # pull this many recent rows from each corpus
    TOP_TERMS        = 20      # extract this many distinctive tokens per corpus
    CANDIDATE_WINDOW = 500     # widen the unread fetch, score, then slice top `limit`
    OVERLAP_SAT      = 5       # overlap saturates at K matches

    module_function

    # Returns the candidate rows scored + sorted, sliced to [offset, limit].
    # Each row gains a `'_score'` key so views can debug-render it later.
    # `state:` and `kind:` mirror ArticlesStore.recent — usually you want
    # state: :unread for a relevance feed.
    def score_window(state: :unread, kind: :all, limit:, offset:, now: Time.now.utc)
      pos_terms = corpus_terms(positive: true)
      neg_terms = corpus_terms(positive: false)

      candidates = ArticlesStore.recent(
        limit:  CANDIDATE_WINDOW,
        offset: 0,
        state:  state,
        kind:   kind
      )

      feed_weights = FeedFeedbackStore.weights_by_feed_id(candidates.map { |a| a['feed_id'] })

      scored = candidates.map do |a|
        a.merge('_score' => score_article(a, pos_terms: pos_terms, neg_terms: neg_terms,
                                              feed_weight: feed_weights[a['feed_id']] || 1.0,
                                              now: now))
      end

      # Stable secondary sort on published_at so ties yield the
      # deterministic "most recent first" the chronological view gives
      # (smaller age = newer = sorts first when scores tie).
      scored.sort_by { |a| [-a['_score'], age_hours(a['published_at'], now)] }
            .drop(offset).first(limit)
    end

    # Pure-compute scorer. Exposed so specs can hit it without a DB
    # round-trip per scenario.
    def score_article(article, pos_terms:, neg_terms:, feed_weight:, now: Time.now.utc)
      tokens   = title_tokens(article)
      pos_hits = (tokens & pos_terms).size
      neg_hits = (tokens & neg_terms).size

      pos_overlap = [pos_hits.to_f / OVERLAP_SAT, 1.0].min
      neg_overlap = [neg_hits.to_f / OVERLAP_SAT, 1.0].min

      recency    = recency_decay(article['published_at'], now)
      pos_factor = 1.0 + POSITIVE_BOOST * pos_overlap
      neg_factor = [NEGATIVE_FLOOR, 1.0 - NEGATIVE_DAMP * neg_overlap].max

      recency * feed_weight * pos_factor * neg_factor
    end

    # Top distinctive tokens across the requested corpus. Returns a Set
    # for O(1) intersection in the per-article scorer. Empty when the
    # corpus has no rows yet (cold start).
    def corpus_terms(positive:)
      rows = positive ? positive_corpus : negative_corpus
      return [].to_set if rows.empty?

      text = rows.map { |r| "#{r['title']} #{r['content_text']}" }.join(' ')
      Recommendation.top_keywords(text, limit: TOP_TERMS).to_set
    end

    def positive_corpus
      Database.connection.execute(<<~SQL, [CORPUS_LIMIT])
        SELECT a.title, a.content_text
        FROM articles a
        JOIN read_state rs ON rs.article_id = a.id
        WHERE rs.bookmarked = 1
           OR rs.feedback = 1
           OR rs.passive_feedback = 1
        ORDER BY a.id DESC
        LIMIT ?
      SQL
    end

    def negative_corpus
      Database.connection.execute(<<~SQL, [CORPUS_LIMIT])
        SELECT a.title, a.content_text
        FROM articles a
        JOIN read_state rs ON rs.article_id = a.id
        WHERE rs.feedback = -1
           OR rs.passive_feedback = -1
           OR (rs.archived = 1 AND rs.read = 0)
        ORDER BY a.id DESC
        LIMIT ?
      SQL
    end

    # Title-only tokens. See module-level comment for the perf rationale.
    def title_tokens(article)
      Recommendation.top_keywords(article['title'].to_s, limit: 1_000).to_set
    end

    # Exponential decay, half-life HALF_LIFE_HOURS. Returns 1.0 for
    # just-published, 0.5 at 48h, 0.25 at 96h, etc.
    def recency_decay(published_at, now)
      age_h = age_hours(published_at, now)
      0.5**(age_h / HALF_LIFE_HOURS.to_f)
    end

    def age_hours(published_at, now)
      return Float::INFINITY if published_at.to_s.empty?
      t = Time.parse(published_at).utc
      diff = (now - t) / 3600.0
      [diff, 0.0].max
    rescue ArgumentError
      Float::INFINITY
    end
  end
end
