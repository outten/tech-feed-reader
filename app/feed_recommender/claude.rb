require 'anthropic'
require 'json'
require_relative '../logger'
require_relative '../tracing'
require_relative '../feed_catalog'
require_relative '../feeds_store'

# STUFF.md #23 — AI-assisted feed recommender.
#
# The user types a free-text prompt on /feeds ("recommendations for
# Anthony-Bourdain-style food + travel content, please") and Claude
# returns 6–8 picks from the curated FeedCatalog — never inventing
# URLs (the catalog is the safety boundary: all entries are
# pre-validated and free).
#
# Personalisation hooks Claude has access to:
#   • What the user is already subscribed to (so we don't double-recommend)
#   • Their existing subscriptions' categories + topics (the AI can lean
#     into "more like what they read" if the prompt hints in that direction)
#
# Stateless on the server: every request is a fresh prompt + the user's
# current subscriptions, no persisted history. If we ever want
# "remember what I asked for last time" that's a follow-up.
module FeedRecommender
  module Claude
    MODEL                 = 'claude-sonnet-4-6'.freeze
    MAX_TOKENS            = 2_000
    MAX_RECOMMENDATIONS   = 8
    MAX_PROMPT_CHARS      = 1_200

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are a feed-recommendation assistant for a personal RSS reader.
      The user will give you a free-text prompt about what they're looking
      for, and you'll be handed a JSON list of CANDIDATE feeds from a
      curated catalog (all already vetted as free + accessible).

      Pick up to %{max} candidates that best match the user's prompt. You
      may also weight your picks by what they're already subscribed to —
      it's fine to lean into "more like what they read" when the prompt
      hints at that, and equally fine to deliberately pick "something
      different" when they ask for discovery.

      Output requirements:
      - Respond with valid JSON only, no prose, no markdown fences.
      - Use this exact schema:
        {
          "recommendations": [
            {"url": "https://...", "rationale": "..."},
            ...
          ]
        }
      - `url` MUST be one of the candidate URLs verbatim. Do not invent
        URLs. Do not modify them.
      - `rationale` is one short sentence (≤20 words) explaining why
        this matches the user's prompt.
      - Order picks best-first.
      - If nothing in the catalog matches, return an empty
        recommendations array.
      - Output exactly one JSON object. No retry, no follow-up.
    PROMPT

    Result = Struct.new(:status, :recommendations, :raw, :model,
                        :latency_ms, :input_tokens, :output_tokens, :error,
                        :prompt, keyword_init: true)

    module_function

    def available?
      !ENV['ANTHROPIC_API_KEY'].to_s.empty?
    end

    # Returns a Result; never raises.
    # status ∈ :ok | :empty | :unavailable | :error | :parse_error | :no_candidates
    def recommend(user_id, prompt:)
      prompt = prompt.to_s.strip
      return Result.new(status: :empty, recommendations: [], prompt: prompt) if prompt.empty?
      return Result.new(status: :unavailable, recommendations: [], prompt: prompt) unless available?

      prompt = prompt[0, MAX_PROMPT_CHARS] if prompt.length > MAX_PROMPT_CHARS

      subscribed_urls = FeedsStore.for_user(user_id).map { |f| f['url'] }.to_set
      candidates      = build_candidates(subscribed_urls)
      if candidates.empty?
        return Result.new(status: :no_candidates, recommendations: [], prompt: prompt)
      end

      subscribed_summary = build_subscribed_summary(subscribed_urls)
      user_message = build_user_message(prompt, candidates, subscribed_summary)
      started      = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      AppLogger.info('feed_recommend_start',
                     model: MODEL, prompt_chars: prompt.length,
                     candidates: candidates.length,
                     subscribed: subscribed_urls.length)

      response = Tracing.in_span(
        'llm.feed_recommend',
        attributes: {
          'llm.vendor'      => 'anthropic',
          'llm.model'       => MODEL,
          'llm.input_chars' => user_message.length,
          'recommend.candidates' => candidates.length,
          'recommend.subscribed' => subscribed_urls.length
        }
      ) do |span|
        r = client.messages.create(
          model:      MODEL.to_sym,
          max_tokens: MAX_TOKENS,
          system_:    format(SYSTEM_PROMPT, max: MAX_RECOMMENDATIONS),
          messages:   [{ role: 'user', content: user_message }]
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
      parsed     = parse_response(raw, candidates)

      AppLogger.info('feed_recommend_done',
                     model:       MODEL,
                     latency_ms:  latency,
                     output_chars: raw.length,
                     picks:       parsed[:recommendations].length,
                     fallback:    parsed[:fallback])

      Result.new(
        status:          parsed[:fallback] ? :parse_error : :ok,
        recommendations: parsed[:recommendations],
        raw:             raw,
        model:           MODEL,
        latency_ms:      latency,
        input_tokens:    (response.usage&.input_tokens&.to_i  if response.respond_to?(:usage)),
        output_tokens:   (response.usage&.output_tokens&.to_i if response.respond_to?(:usage)),
        prompt:          prompt,
        error:           parsed[:error]
      )
    rescue Anthropic::Errors::APIError => e
      AppLogger.error('feed_recommend', status: :error, class: e.class.name, message: e.message)
      Result.new(status: :error, recommendations: [], prompt: prompt,
                 error: "#{e.class.name}: #{e.message}")
    rescue StandardError => e
      AppLogger.error('feed_recommend', status: :error, class: e.class.name, message: e.message)
      Result.new(status: :error, recommendations: [], prompt: prompt,
                 error: "#{e.class.name}: #{e.message}")
    end

    # Catalog rows the user isn't already subscribed to. Returns
    # condensed hashes ready for JSON serialization in the prompt.
    def build_candidates(subscribed_urls)
      FeedCatalog::CATALOG.reject { |entry| subscribed_urls.include?(entry[:url]) }.map do |entry|
        {
          url:      entry[:url],
          title:    entry[:title],
          category: entry[:category].to_s,
          topic:    FeedCatalog.topic_for(entry).to_s,
          blurb:    entry[:blurb].to_s
        }
      end
    end

    # Compact view of what the user is already subscribed to — sent to
    # Claude as personalisation context. Grouped by topic so the prompt
    # stays short even with hundreds of subs.
    def build_subscribed_summary(subscribed_urls)
      return { count: 0, by_topic: {} } if subscribed_urls.empty?

      by_topic = Hash.new { |h, k| h[k] = [] }
      FeedCatalog::CATALOG.each do |entry|
        next unless subscribed_urls.include?(entry[:url])
        by_topic[FeedCatalog.topic_for(entry).to_s] << entry[:title]
      end
      # Cap each topic to the first 12 titles so a very-subscribed user
      # doesn't bloat the prompt; the count below tells Claude the rest.
      by_topic.each_value { |titles| titles.replace(titles.first(12)) }
      { count: subscribed_urls.length, by_topic: by_topic }
    end

    def build_user_message(prompt, candidates, subscribed_summary)
      <<~MSG
        ## User's request
        #{prompt}

        ## Currently subscribed (for personalisation context)
        #{JSON.generate(subscribed_summary)}

        ## Candidate feeds (pick from these — never invent URLs)
        #{JSON.generate(candidates)}
      MSG
    end

    # Parse Claude's JSON response. Strips a possible markdown fence,
    # validates each picked URL against the candidate set, attaches the
    # catalog metadata (title, blurb, topic, category) so the view
    # doesn't have to re-look-up. On parse failure returns
    # {fallback: true, recommendations: [], error: '…'} so the route
    # can surface a friendly message instead of 500ing.
    def parse_response(raw, candidates)
      stripped = strip_markdown_fence(raw)
      json     = JSON.parse(stripped)
      picks    = Array(json['recommendations'])
      catalog  = candidates.each_with_object({}) { |c, h| h[c[:url]] = c }

      seen = {}
      recommendations = picks.filter_map do |p|
        url = p['url'].to_s
        next if seen.key?(url)
        meta = catalog[url]
        next unless meta
        seen[url] = true
        meta.merge(rationale: p['rationale'].to_s.strip)
      end
      { fallback: false, recommendations: recommendations.first(MAX_RECOMMENDATIONS), error: nil }
    rescue JSON::ParserError => e
      { fallback: true, recommendations: [], error: "JSON parse failed: #{e.message}" }
    end

    # Tolerates "```json\n{...}\n```" or plain "{...}". Keeps the
    # parser resilient if the model slips in a fence despite the
    # system prompt forbidding it.
    def strip_markdown_fence(raw)
      s = raw.strip
      return s unless s.start_with?('```')
      s.sub(/\A```(?:json)?\s*/, '').sub(/\s*```\z/, '').strip
    end

    class << self
      private

      def client
        @client ||= Anthropic::Client.new
      end
    end
  end
end
