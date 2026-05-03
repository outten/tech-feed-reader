require 'anthropic'
require_relative '../logger'
require_relative '../metrics'

# LLM summary backend. One-shot Anthropic API call per "Summarize with
# Claude" click on /article/:uid. Output lands in summaries.llm +
# summaries.llm_model, side-by-side with the always-on extractive
# summary so the article view can show both.
#
# Cached forever per article id — re-summarizing only happens when the
# user explicitly clicks (mirrors AGENTS.md gotcha #7: LLM summaries
# are EXPENSIVE; don't invalidate on feed re-fetch).
#
# Graceful when ANTHROPIC_API_KEY is unset: .available? returns false,
# the route hides the button, the .summarize call returns an error
# struct rather than raising. The whole feature is opt-in.
module Summarizer
  module Claude
    MODEL       = 'claude-opus-4-7'.freeze
    MAX_TOKENS  = 600
    MAX_CONTENT = 60_000  # chars; ~15K tokens. Plenty of headroom on Opus 4.7's 1M context.

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert article summarizer. Given the title and body of an
      article, write a tight 3–5 sentence summary that captures the key
      points and the main takeaway. Be neutral, factual, and informative.
      Skip preambles like "This article discusses..." — go straight to the
      content. Do not add commentary, opinion, or your own framing.
    PROMPT

    Result = Struct.new(:status, :text, :model, :error, keyword_init: true)

    module_function

    def available?
      !ENV['ANTHROPIC_API_KEY'].to_s.empty?
    end

    # Returns a Result. status is :ok on success, :unavailable if no API
    # key, :empty if the article has no content, :error otherwise.
    def summarize(title:, content_text:)
      unless available?
        AppLogger.warn('claude_summarize', status: :unavailable, reason: 'ANTHROPIC_API_KEY not set')
        return Result.new(status: :unavailable)
      end

      body = content_text.to_s.strip
      if body.empty?
        AppLogger.info('claude_summarize', status: :empty, title: title)
        return Result.new(status: :empty)
      end

      body    = body[0, MAX_CONTENT]
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      AppLogger.info('claude_summarize_start', model: MODEL, title: title, body_length: body.length)
      response = client.messages.create(
        model:      MODEL.to_sym,
        max_tokens: MAX_TOKENS,
        system_:    SYSTEM_PROMPT,
        messages:   [
          { role: 'user', content: "Title: #{title}\n\n#{body}" }
        ]
      )
      latency = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

      text_block = response.content.find { |b| b.type == :text }
      text       = text_block&.text.to_s.strip
      if text.empty?
        AppLogger.warn('claude_summarize', status: :error, reason: 'empty response', latency_ms: latency)
        return Result.new(status: :error, error: 'empty response')
      end

      AppLogger.info('claude_summarize_done', model: MODEL, latency_ms: latency, output_length: text.length)
      Metrics::SUMMARIES_GENERATED.increment(labels: { kind: 'llm' })
      Result.new(status: :ok, text: text, model: MODEL)
    rescue Anthropic::Errors::APIError => e
      AppLogger.error('claude_summarize', status: :error, class: e.class.name, message: e.message)
      Result.new(status: :error, error: "#{e.class.name}: #{e.message}")
    rescue StandardError => e
      AppLogger.error('claude_summarize', status: :error, class: e.class.name, message: e.message)
      Result.new(status: :error, error: "#{e.class.name}: #{e.message}")
    end

    class << self
      private

      def client
        @client ||= Anthropic::Client.new
      end
    end
  end
end
