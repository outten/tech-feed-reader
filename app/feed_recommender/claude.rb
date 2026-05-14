require 'anthropic'
require 'json'
require_relative '../logger'
require_relative '../tracing'
require_relative '../feeds_store'
require_relative 'validator'

# STUFF.md #23 — AI-assisted feed discovery.
#
# The user types a free-text prompt on /feeds and Claude suggests
# specific real feeds (RSS, podcast, or YouTube channel feeds) from
# its training knowledge that match. **The curated FeedCatalog is NOT
# the source** — the catalog is a separate "Recommended for you"
# callout. This module is for discovering NEW feeds outside the
# catalog.
#
# Hallucination guard: Claude is told not to invent URLs, but it
# will anyway. So every URL Claude returns goes through
# FeedRecommender::Validator, which fetches it + tries to parse it as
# a feed. We only surface validated picks. Failed ones are logged but
# hidden from the user (the user picked "Hide them" in the design
# question — see STUFF #23 thread).
#
# Latency profile: ~1.5s Claude round-trip + ~5s validation batch
# (parallel, capped) = ~6.5s typical, ~12s worst case.
module FeedRecommender
  module Claude
    MODEL                 = 'claude-sonnet-4-6'.freeze
    MAX_TOKENS            = 2_000
    MAX_RECOMMENDATIONS   = 8
    MAX_PROMPT_CHARS      = 1_200

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are a feed-discovery assistant for a personal RSS reader.
      The user gives you a free-text prompt; you respond with specific,
      real, free, publicly accessible feeds that match.

      You may suggest:
      - RSS / Atom feeds (blogs, publishers, news)
      - Podcast feeds (RSS with audio enclosures)
      - YouTube channel feeds, using the canonical URL pattern
        https://www.youtube.com/feeds/videos.xml?channel_id=<UC...>
        (only when you remember the channel ID with high confidence)

      Hard rules:
      - Suggest ONLY feeds you remember are real and have a stable, public
        URL. Don't invent URLs. Don't guess. If you only know the website,
        skip it — the user can find the RSS link themselves.
      - All feeds must be FREE (no paywall, no auth, no subscription).
      - Don't repeat URLs the user is already subscribed to (a list is
        provided in the user message).
      - Up to %{max} picks. Order best-first.
      - **Aim for a mix of kinds** (RSS blogs, podcasts, YouTube channels)
        when the topic supports it. Don't return all-of-one-kind unless
        that's genuinely what fits the request — variety is a feature.
      - For YouTube: only include a channel if you remember its exact
        channel ID (the `UC…` token in the URL). Don't guess the ID — a
        wrong one will 404. If you only remember the channel name or
        `@handle`, skip it.

      Output requirements:
      - Valid JSON only. No prose, no markdown fences.
      - Schema:
        {
          "recommendations": [
            {
              "url":       "https://...",
              "title":     "Human-friendly name",
              "kind":      "rss" | "podcast" | "youtube",
              "rationale": "one short sentence (≤20 words) connecting to the prompt"
            },
            ...
          ]
        }
      - If you don't know any matching feeds, return {"recommendations": []}.
      - Output exactly one JSON object. No retry, no follow-up.
    PROMPT

    Result = Struct.new(:status, :recommendations, :raw, :model,
                        :latency_ms, :input_tokens, :output_tokens, :error,
                        :prompt, :suggested_count, :validated_count,
                        :kind_breakdown, keyword_init: true)

    module_function

    def available?
      !ENV['ANTHROPIC_API_KEY'].to_s.empty?
    end

    # Returns a Result; never raises.
    # status ∈ :ok | :empty | :unavailable | :error | :parse_error | :no_validated
    def recommend(user_id, prompt:)
      prompt = prompt.to_s.strip
      return Result.new(status: :empty, recommendations: [], prompt: prompt,
                        suggested_count: 0, validated_count: 0) if prompt.empty?
      return Result.new(status: :unavailable, recommendations: [], prompt: prompt,
                        suggested_count: 0, validated_count: 0) unless available?

      prompt = prompt[0, MAX_PROMPT_CHARS] if prompt.length > MAX_PROMPT_CHARS

      subscribed_titles, subscribed_urls = subscribed_lists(user_id)
      user_message = build_user_message(prompt, subscribed_titles, subscribed_urls)
      started      = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      AppLogger.info('feed_recommend_start',
                     model: MODEL, prompt_chars: prompt.length,
                     subscribed: subscribed_urls.length)

      response = Tracing.in_span(
        'llm.feed_recommend',
        attributes: {
          'llm.vendor'      => 'anthropic',
          'llm.model'       => MODEL,
          'llm.input_chars' => user_message.length,
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
      parsed     = parse_response(raw, subscribed_urls)

      if parsed[:fallback]
        AppLogger.warn('feed_recommend_parse_error', error: parsed[:error], raw: raw[0, 500])
        return Result.new(
          status: :parse_error, recommendations: [], prompt: prompt,
          raw: raw, model: MODEL, latency_ms: latency,
          input_tokens: token_in(response), output_tokens: token_out(response),
          error: parsed[:error], suggested_count: 0, validated_count: 0
        )
      end

      suggestions = parsed[:recommendations]
      AppLogger.info('feed_recommend_llm_done',
                     model: MODEL, latency_ms: latency, suggested: suggestions.length)

      # Validate every Claude-suggested URL by fetching + parsing it.
      # Keep only :ok; failed ones are logged but hidden.
      validation_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      validation_results = Validator.validate_many(suggestions.map { |s| s[:url] })
      validation_latency = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - validation_started) * 1000).round

      validated = []
      # Per-kind diagnostic: which kinds Claude suggested vs. which
      # actually validated. Surfaced in the result for the view ("Kinds
      # suggested: rss × 4, podcast × 2, youtube × 2; validated: rss × 1,
      # podcast × 2, youtube × 0") so the user can see when validation
      # is gating one kind disproportionately.
      breakdown = { suggested: Hash.new(0), validated: Hash.new(0) }
      suggestions.zip(validation_results).each do |sug, val|
        kind = sug[:kind] || 'rss'
        breakdown[:suggested][kind] += 1
        if val.status == :ok
          # Prefer the feed's self-reported title over Claude's guess.
          title = val.title.to_s.empty? ? sug[:title] : val.title
          validated << sug.merge(
            title:       title,
            image_url:   val.image_url,
            entry_count: val.entry_count
          )
          breakdown[:validated][kind] += 1
        else
          AppLogger.info('feed_recommend_validate_skip',
                         url: sug[:url], kind: kind, status: val.status, error: val.error)
        end
      end

      AppLogger.info('feed_recommend_done',
                     model:               MODEL,
                     llm_latency_ms:      latency,
                     validate_latency_ms: validation_latency,
                     suggested:           suggestions.length,
                     validated:           validated.length,
                     kind_suggested:      breakdown[:suggested],
                     kind_validated:      breakdown[:validated])

      total_latency = latency + validation_latency
      Result.new(
        status:          validated.empty? ? :no_validated : :ok,
        recommendations: validated.first(MAX_RECOMMENDATIONS),
        raw:             raw,
        model:           MODEL,
        latency_ms:      total_latency,
        input_tokens:    token_in(response),
        output_tokens:   token_out(response),
        prompt:          prompt,
        suggested_count: suggestions.length,
        validated_count: validated.length,
        kind_breakdown:  breakdown,
        error:           nil
      )
    rescue Anthropic::Errors::APIError => e
      AppLogger.error('feed_recommend', status: :error, class: e.class.name, message: e.message)
      Result.new(status: :error, recommendations: [], prompt: prompt,
                 error: "#{e.class.name}: #{e.message}",
                 suggested_count: 0, validated_count: 0)
    rescue StandardError => e
      AppLogger.error('feed_recommend', status: :error, class: e.class.name, message: e.message)
      Result.new(status: :error, recommendations: [], prompt: prompt,
                 error: "#{e.class.name}: #{e.message}",
                 suggested_count: 0, validated_count: 0)
    end

    # Subscribed-feed context for Claude: titles (for personalization
    # cues) + URL set (so Claude can be told what to exclude).
    def subscribed_lists(user_id)
      rows = FeedsStore.for_user(user_id)
      titles = rows.map { |f| (f['title'].to_s.empty? ? f['url'] : f['title']) }.uniq.first(80)
      urls   = rows.map { |f| f['url'].to_s }.to_set
      [titles, urls]
    end

    def build_user_message(prompt, subscribed_titles, subscribed_urls)
      sub_block = subscribed_titles.empty? ?
        '(none — this user is starting fresh)' :
        JSON.generate(subscribed_titles)

      <<~MSG
        ## User's request
        #{prompt}

        ## Currently subscribed titles (for personalisation; avoid recommending the same source)
        #{sub_block}

        ## Already-subscribed URLs (skip these in your output)
        #{JSON.generate(subscribed_urls.to_a)}
      MSG
    end

    # Parse Claude's JSON response. Strips a possible markdown fence and
    # drops any url the user is already subscribed to.
    def parse_response(raw, subscribed_urls)
      stripped = strip_markdown_fence(raw)
      json     = JSON.parse(stripped)
      picks    = Array(json['recommendations'])

      seen = {}
      recommendations = picks.filter_map do |p|
        url = p['url'].to_s.strip
        next if url.empty?
        next if seen.key?(url)
        next if subscribed_urls.include?(url)
        seen[url] = true
        {
          url:       url,
          title:     p['title'].to_s.strip,
          kind:      normalise_kind(p['kind']),
          rationale: p['rationale'].to_s.strip
        }
      end
      { fallback: false, recommendations: recommendations.first(MAX_RECOMMENDATIONS), error: nil }
    rescue JSON::ParserError => e
      { fallback: true, recommendations: [], error: "JSON parse failed: #{e.message}" }
    end

    def normalise_kind(k)
      v = k.to_s.downcase.strip
      %w[rss podcast youtube].include?(v) ? v : 'rss'
    end

    # Tolerates "```json\n{...}\n```" or plain "{...}".
    def strip_markdown_fence(raw)
      s = raw.strip
      return s unless s.start_with?('```')
      s.sub(/\A```(?:json)?\s*/, '').sub(/\s*```\z/, '').strip
    end

    def token_in(response)
      response.usage&.input_tokens&.to_i if response.respond_to?(:usage)
    end

    def token_out(response)
      response.usage&.output_tokens&.to_i if response.respond_to?(:usage)
    end

    class << self
      private

      def client
        @client ||= Anthropic::Client.new
      end
    end
  end
end
