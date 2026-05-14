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
    #
    # Phase S10 — `topic:` scopes both corpus selection AND the
    # candidate window so a 👍 on an Eagles article doesn't boost
    # tech rankings (and vice versa). nil = unscoped (legacy
    # behaviour, used when no topic filter is in effect).
    def score_window(user_id = 1, state: :unread, kind: :all, limit:, offset:, topic: nil, now: Time.now.utc)
      pos_terms = corpus_terms(user_id, positive: true,  topic: topic)
      neg_terms = corpus_terms(user_id, positive: false, topic: topic)

      candidates = ArticlesStore.recent(
        user_id,
        limit:  CANDIDATE_WINDOW,
        offset: 0,
        state:  state,
        kind:   kind,
        topic:  topic
      )

      feed_weights = FeedFeedbackStore.weights_by_feed_id(user_id, candidates.map { |a| a['feed_id'] })

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
    # corpus has no rows yet (cold start). Phase S10: `topic:` scopes
    # the SQL to articles whose feed.topic matches.
    def corpus_terms(user_id = 1, positive:, topic: nil)
      rows = positive ? positive_corpus(user_id, topic: topic) : negative_corpus(user_id, topic: topic)
      return [].to_set if rows.empty?

      text = rows.map { |r| "#{r['title']} #{r['content_text']}" }.join(' ')
      Recommendation.top_keywords(text, limit: TOP_TERMS).to_set
    end

    def positive_corpus(user_id = 1, topic: nil)
      sql = <<~SQL
        SELECT a.title, a.content_text
        FROM articles a
        JOIN read_state rs ON rs.article_id = a.id AND rs.user_id = ?
        #{'JOIN feeds f ON f.id = a.feed_id' if topic}
        WHERE (rs.bookmarked = 1
           OR rs.feedback = 1
           OR rs.passive_feedback = 1)
        #{'AND f.topic = ?' if topic}
        ORDER BY a.id DESC
        LIMIT ?
      SQL
      args = [user_id.to_i]
      args << topic.to_s if topic
      args << CORPUS_LIMIT
      Database.connection.execute(sql, args)
    end

    def negative_corpus(user_id = 1, topic: nil)
      sql = <<~SQL
        SELECT a.title, a.content_text
        FROM articles a
        JOIN read_state rs ON rs.article_id = a.id AND rs.user_id = ?
        #{'JOIN feeds f ON f.id = a.feed_id' if topic}
        WHERE (rs.feedback = -1
           OR rs.passive_feedback = -1
           OR (rs.archived = 1 AND rs.read = 0))
        #{'AND f.topic = ?' if topic}
        ORDER BY a.id DESC
        LIMIT ?
      SQL
      args = [user_id.to_i]
      args << topic.to_s if topic
      args << CORPUS_LIMIT
      Database.connection.execute(sql, args)
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

    # Phase 7 — single-suggestion picker for the "Read next" card on
    # /article/:uid. Returns the highest-scored unread article that
    # isn't `article` itself, or nil if the user has no positive
    # corpus yet (caller falls back to FTS5 "Related"). The "no
    # positive corpus" check is what differentiates the personalised
    # signal from chronological — when there's nothing to personalise
    # against, FTS5 content-similarity is the better fallback.
    def next_after(*args, now: Time.now.utc)
      user_id, article = args.length == 2 ? args : [1, args.first]
      return nil if article.nil?
      return nil if positive_corpus(user_id).empty?

      ranked = score_window(user_id, state: :unread, limit: 25, offset: 0, now: now)
      ranked.find { |a| a['id'] != article['id'] }
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
