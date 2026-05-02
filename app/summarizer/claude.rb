require 'anthropic'

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
      return Result.new(status: :unavailable) unless available?

      body = content_text.to_s.strip
      return Result.new(status: :empty) if body.empty?

      body = body[0, MAX_CONTENT]
      response = client.messages.create(
        model:      MODEL.to_sym,
        max_tokens: MAX_TOKENS,
        system_:    SYSTEM_PROMPT,
        messages:   [
          { role: 'user', content: "Title: #{title}\n\n#{body}" }
        ]
      )

      text_block = response.content.find { |b| b.type == :text }
      text       = text_block&.text.to_s.strip
      return Result.new(status: :error, error: 'empty response') if text.empty?

      Result.new(status: :ok, text: text, model: MODEL)
    rescue Anthropic::Errors::APIError => e
      Result.new(status: :error, error: "#{e.class.name}: #{e.message}")
    rescue StandardError => e
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
