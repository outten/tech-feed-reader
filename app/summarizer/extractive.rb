require 'set'

# Pure-Ruby extractive summarizer. Picks the top N sentences from a
# document by scoring each sentence on the sum of its non-stopword
# token frequencies, normalised by sentence length so we don't bias
# toward long-winded ones.
#
# Lead-3 + frequency hybrid: the ranking always includes the first
# sentence (news-summary convention) plus up to (target - 1) more from
# the highest-scoring rest, returned in the original document order.
#
# This is deliberately simple — TextRank-style graph ranking is
# overkill for ~200-1500 word feed entries and would add a graph
# dependency. A frequency-based picker captures the gist with no
# external libraries.
module Summarizer
  module Extractive
    DEFAULT_SENTENCES = 3
    MIN_SENTENCE_LEN  = 4   # word tokens
    MAX_SENTENCE_LEN  = 80  # word tokens; chops up giant block paragraphs

    # Common English stopwords. Not exhaustive but covers the bulk of
    # term-frequency noise. Lowercase; punctuation stripped before lookup.
    STOPWORDS = %w[
      a about above after again against all am an and any are aren as at
      be because been before being below between both but by could
      did didn do does doesn doing don down during each
      few for from further had hadn has hasn have haven having he her here
      hers herself him himself his how i if in into is isn it its itself
      just like
      ll m me might more most mustn my myself
      no nor not now
      of off on once only or other our ours ourselves out over own
      re s same shan she should shouldn so some such
      t than that the their theirs them themselves then there these they
      this those through to too
      under until up
      ve very
      was wasn we were weren what when where which while who whom why will with won would
      y you your yours yourself yourselves
    ].to_set.freeze

    SENTENCE_BOUNDARY = /(?<=[.!?])\s+(?=[A-Z0-9"'(])/

    module_function

    # `text` is the plain-text article body (already loofah-extracted by
    # FeedParser). `sentences` is the target picked-sentence count;
    # documents shorter than the target are returned in full.
    # Returns a String — joined picked sentences with a single space
    # between them.
    def summarize(text, sentences: DEFAULT_SENTENCES)
      return '' if text.to_s.strip.empty?

      raw = split_sentences(text)
      return raw.join(' ') if raw.length <= sentences

      tokens_per_sentence = raw.map { |s| tokenize(s) }
      freq = word_frequencies(tokens_per_sentence)

      scored = raw.each_with_index.map do |sentence, i|
        toks = tokens_per_sentence[i]
        next [i, sentence, -1.0] if toks.length < MIN_SENTENCE_LEN

        keepable = toks.first(MAX_SENTENCE_LEN)
        score    = keepable.sum { |t| freq[t] || 0 }.to_f / keepable.length
        [i, sentence, score]
      end

      # Always include the first sentence (lead-bias for news content);
      # then take the top-(N-1) of the remainder by score, preserving
      # original document order on output.
      lead   = [scored.first]
      others = scored[1..].sort_by { |_, _, score| -score }.first(sentences - 1)
      picked = (lead + others).sort_by { |i, _, _| i }
      picked.map { |_, s, _| s }.join(' ')
    end

    class << self
      private

      def split_sentences(text)
        text.to_s.gsub(/\s+/, ' ').strip.split(SENTENCE_BOUNDARY).reject(&:empty?)
      end

      def tokenize(sentence)
        sentence
          .downcase
          .scan(/[a-z][a-z'-]*/)
          .reject { |w| STOPWORDS.include?(w) }
      end

      def word_frequencies(tokens_per_sentence)
        freq = Hash.new(0)
        tokens_per_sentence.flatten.each { |t| freq[t] += 1 }
        freq
      end
    end
  end
end
