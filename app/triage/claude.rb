require 'anthropic'
require 'json'
require_relative '../logger'
require_relative '../tracing'
require_relative '../articles_store'
require_relative '../read_state_store'
require_relative '../feed_feedback_store'
require_relative '../recommendation/for_you'

# Phase 8 — AI-assisted daily triage. Claude reads today's unread + a
# small sample of the user's positive/negative corpus and classifies
# each unread article into one of three groups: must_read / optional /
# skip, each with a one-sentence rationale.
#
# Differs from Summarizer::Claude:
#   - Sonnet, not Opus (cost guard — TODO.md says claude-sonnet-4-6)
#   - Stateless: no DB persistence v1; computed on-demand from POST /triage.
#   - Structured JSON output (system prompt enforces, parser is
#     defensive — strips markdown fences, falls through to a "skip
#     all" result on parse failure rather than 500ing the page).
#
# Cost guard: 30 articles × ~1KB excerpt + 20 corpus exemplars × ~200
# chars = ~32 KB input, ~5K input tokens. Output ~2K tokens. Per call
# cost on Sonnet 4.6 is ~$0.02–0.04 — fine for personal-use,
# user-triggered manual runs.
module Triage
  module Claude
    MODEL                 = 'claude-sonnet-4-6'.freeze
    MAX_TOKENS            = 4_000
    UNREAD_LIMIT          = 30
    CORPUS_EXEMPLAR_LIMIT = 20
    EXCERPT_CHARS         = 1_000
    EXEMPLAR_CHARS        = 200

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert reading-list triage assistant. Given the user's
      unread queue plus a small sample of articles they previously liked
      (positive corpus) and didn't like (negative corpus), classify each
      unread article into exactly one of three groups: must_read (high
      relevance to the user's interests), optional (might interest, could
      go either way), skip (low relevance — they probably don't want to
      spend time on it).

      Output requirements:
      - Respond with valid JSON only, no prose, no markdown fences.
      - Use this exact schema:
        {
          "must_read": [{"uid": "...", "rationale": "..."}],
          "optional":  [{"uid": "...", "rationale": "..."}],
          "skip":      [{"uid": "...", "rationale": "..."}]
        }
      - Every unread article appears in exactly one group.
      - Rationale is one short sentence, max 15 words, citing the corpus
        signal that drove the classification ("matches your bookmarked
        Ruby work" / "topic you've previously demoted" / etc.).
      - Output exactly one JSON object. Do not retry, restart, or write
        a "let me redo this" follow-up — finalize the JSON and stop. Do
        not include any text before or after the JSON object.
    PROMPT

    Result = Struct.new(:status, :must_read, :optional, :skip, :raw, :model,
                        :latency_ms, :input_tokens, :output_tokens, :error,
                        :unread_count, :topic, keyword_init: true)

    module_function

    def available?
      !ENV['ANTHROPIC_API_KEY'].to_s.empty?
    end

    # Top-level entry point. Returns a Result; never raises. Empty
    # unread queue → Result.status :empty (caller renders an "all
    # caught up" view rather than a triage). No API key → :unavailable.
    # Phase S10 — `topic:` scopes the unread queue + corpus
    # exemplars to a single topic (tech / sports / general). nil
    # means cross-topic, the legacy behaviour.
    def run(topic: nil)
      return Result.new(status: :unavailable, unread_count: 0, topic: topic) unless available?

      unread = ArticlesStore.recent(limit: UNREAD_LIMIT, state: :unread, topic: topic)
      if unread.empty?
        AppLogger.info('triage_run', status: :empty, topic: topic)
        return Result.new(status: :empty, unread_count: 0, topic: topic,
                          must_read: [], optional: [], skip: [])
      end

      positive = corpus_exemplars(positive: true,  topic: topic)
      negative = corpus_exemplars(positive: false, topic: topic)

      prompt   = build_user_prompt(unread, positive, negative)
      started  = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      AppLogger.info('triage_run_start', model: MODEL, unread: unread.length,
                                          positive: positive.length, negative: negative.length)

      response = Tracing.in_span(
        'llm.triage',
        attributes: {
          'llm.vendor'      => 'anthropic',
          'llm.model'       => MODEL,
          'llm.input_chars' => prompt.length,
          'triage.unread'   => unread.length,
          'triage.positive' => positive.length,
          'triage.negative' => negative.length
        }
      ) do |span|
        r = client.messages.create(
          model:      MODEL.to_sym,
          max_tokens: MAX_TOKENS,
          system_:    SYSTEM_PROMPT,
          messages:   [{ role: 'user', content: prompt }]
        )
        if span.respond_to?(:set_attribute) && r.respond_to?(:usage) && r.usage
          span.set_attribute('llm.input_tokens',  r.usage.input_tokens.to_i)
          span.set_attribute('llm.output_tokens', r.usage.output_tokens.to_i)
        end
        r
      end
      latency = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

      text_block = response.content.find { |b| b.type == :text }
      raw        = text_block&.text.to_s.strip
      parsed     = parse_response(raw, unread)

      AppLogger.info('triage_run_done',
                     model:        MODEL,
                     latency_ms:   latency,
                     output_chars: raw.length,
                     must_read:    parsed[:must_read].length,
                     optional:     parsed[:optional].length,
                     skip:         parsed[:skip].length,
                     fallback:     parsed[:fallback])

      Result.new(
        status:        parsed[:fallback] ? :parse_error : :ok,
        must_read:     parsed[:must_read],
        optional:      parsed[:optional],
        skip:          parsed[:skip],
        raw:           raw,
        model:         MODEL,
        latency_ms:    latency,
        input_tokens:  (response.usage&.input_tokens&.to_i if response.respond_to?(:usage)),
        output_tokens: (response.usage&.output_tokens&.to_i if response.respond_to?(:usage)),
        unread_count:  unread.length,
        topic:         topic,
        error:         parsed[:error]
      )
    rescue Anthropic::Errors::APIError => e
      AppLogger.error('triage_run', status: :error, class: e.class.name, message: e.message)
      Result.new(status: :error, error: "#{e.class.name}: #{e.message}", unread_count: 0, topic: topic,
                 must_read: [], optional: [], skip: [])
    rescue StandardError => e
      AppLogger.error('triage_run', status: :error, class: e.class.name, message: e.message)
      Result.new(status: :error, error: "#{e.class.name}: #{e.message}", unread_count: 0, topic: topic,
                 must_read: [], optional: [], skip: [])
    end

    # Build the user-message prompt. Each section has a heading + a
    # bullet list. Excerpts are length-capped per the cost guard.
    def build_user_prompt(unread, positive, negative)
      lines = []
      lines << '## Positive corpus (articles I liked / engaged with):'
      lines.concat(positive.empty? ? ['(none yet — cold start)'] : positive.map { |r| format_exemplar(r) })
      lines << ''
      lines << '## Negative corpus (articles I disliked / skipped):'
      lines.concat(negative.empty? ? ['(none yet)'] : negative.map { |r| format_exemplar(r) })
      lines << ''
      lines << '## Unread articles to triage:'
      lines.concat(unread.map { |a| format_unread(a) })
      lines.join("\n")
    end

    # Defensive parser. Tries, in order:
    #   1. Strict JSON.parse on the whole string (happy path).
    #   2. Strip leading/trailing ```json fences and try again.
    #   3. Extract every brace-balanced top-level {...} block via
    #      extract_json_candidates and try each from LAST to FIRST.
    #      Last-first matters: when Sonnet 4.6 second-guesses itself
    #      mid-response ("Wait, I made errors. Let me redo:" + a
    #      second JSON block), the corrected output is the last block.
    #   4. Fall through to a "skip-all" Result with status :parse_error.
    #
    # Returns a hash with :must_read/:optional/:skip arrays and a
    # :fallback flag set true when we couldn't parse.
    def parse_response(raw, unread)
      cleaned = raw.dup
      cleaned.sub!(/\A```(?:json)?\s*/, '')
      cleaned.sub!(/\s*```\s*\z/, '')
      groups_from_hash(JSON.parse(cleaned))
    rescue JSON::ParserError, TypeError => e
      # Salvage: try every brace-balanced JSON object from last to first.
      extract_json_candidates(raw).reverse.each do |candidate|
        begin
          data = JSON.parse(candidate)
          next unless data.is_a?(Hash) && schema_match?(data)
          return groups_from_hash(data)
        rescue JSON::ParserError
          next
        end
      end

      AppLogger.warn('triage_parse', status: :fallback, message: e.message,
                                      raw_head: raw.to_s[0, 200])
      {
        must_read: [],
        optional:  [],
        skip:      unread.map { |a| { 'uid' => a['uid'], 'rationale' => 'unparsed — see raw output' } },
        fallback:  true,
        error:     "parse failure: #{e.class.name}: #{e.message}"
      }
    end

    def groups_from_hash(data)
      raise TypeError, 'expected Hash' unless data.is_a?(Hash)
      groups = %w[must_read optional skip].each_with_object({}) do |key, h|
        h[key.to_sym] = Array(data[key]).map do |entry|
          next unless entry.is_a?(Hash)
          { 'uid' => entry['uid'].to_s, 'rationale' => entry['rationale'].to_s }
        end.compact
      end
      groups[:fallback] = false
      groups[:error]    = nil
      groups
    end

    # A response shape is "good enough" if it has at least one of
    # the three group keys — guards against returning a parsed-but-
    # unrelated JSON blob if the model embeds one (e.g. a quoted
    # rationale that happens to be a tiny JSON object).
    def schema_match?(hash)
      %w[must_read optional skip].any? { |k| hash.key?(k) }
    end

    # Walk the raw text and emit every top-level brace-balanced
    # {...} substring. Tracks string-literal context so braces
    # inside JSON strings (e.g. a rationale like "'{example}'")
    # don't break the depth counter. Returns substrings in source
    # order — callers that want the latest object should reverse.
    def extract_json_candidates(text)
      objects = []
      depth = 0
      start = nil
      in_string = false
      escape = false
      text.each_char.with_index do |c, i|
        if in_string
          if escape
            escape = false
          elsif c == '\\'
            escape = true
          elsif c == '"'
            in_string = false
          end
          next
        end
        case c
        when '"'
          in_string = true
        when '{'
          start = i if depth.zero?
          depth += 1
        when '}'
          if depth.positive?
            depth -= 1
            if depth.zero? && start
              objects << text[start..i]
              start = nil
            end
          end
        end
      end
      objects
    end

    def format_exemplar(row)
      excerpt = row['content_text'].to_s.gsub(/\s+/, ' ').strip[0, EXEMPLAR_CHARS]
      excerpt = "#{excerpt[0, EXEMPLAR_CHARS - 1]}…" if excerpt.length == EXEMPLAR_CHARS
      "- \"#{row['title']}\" — #{excerpt}"
    end

    def format_unread(row)
      excerpt = row['content_text'].to_s.gsub(/\s+/, ' ').strip[0, EXCERPT_CHARS]
      excerpt = "#{excerpt[0, EXCERPT_CHARS - 1]}…" if excerpt.length == EXCERPT_CHARS
      "- uid=#{row['uid']} \"#{row['title']}\" — #{excerpt}"
    end

    # Pull recent positive / negative exemplars for the prompt — same
    # corpus shape the For You ranker uses, just capped to the
    # exemplar count and sliced to title + content_text.
    def corpus_exemplars(positive:, topic: nil)
      where_corpus = positive ?
        '(rs.bookmarked = 1 OR rs.feedback = 1 OR rs.passive_feedback = 1)' :
        '(rs.feedback = -1 OR rs.passive_feedback = -1 OR (rs.archived = 1 AND rs.read = 0))'
      sql = <<~SQL
        SELECT a.title, a.content_text
        FROM articles a
        JOIN read_state rs ON rs.article_id = a.id
        #{'JOIN feeds f ON f.id = a.feed_id' if topic}
        WHERE #{where_corpus}
        #{'AND f.topic = ?' if topic}
        ORDER BY a.id DESC
        LIMIT ?
      SQL
      Database.connection.execute(sql, topic ? [topic.to_s, CORPUS_EXEMPLAR_LIMIT] : [CORPUS_EXEMPLAR_LIMIT])
    end

    class << self
      private

      def client
        @client ||= Anthropic::Client.new
      end
    end
  end
end
