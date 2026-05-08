require 'anthropic'
require_relative 'logger'
require_relative 'metrics'
require_relative 'tracing'

# Chat backend for the floating chat widget. Stateless on the server —
# the widget stores the message history in localStorage (keyed by page
# URL) and replays it on every POST /chat. That keeps the server
# trivial (no session table, no auth flow) and lets each page have
# its own thread without any plumbing.
#
# Each turn ships:
#   - the page context (url, title, excerpt) so the assistant can
#     answer questions about whatever the user is looking at
#   - the prior turns (capped to MAX_HISTORY_TURNS so token cost
#     doesn't blow up over a long conversation)
#   - the new user message
#
# Model choice: claude-sonnet-4-6 — fast enough for interactive chat
# while still strong on the kind of "what is this article saying"
# follow-ups the widget is built for. The Summarizer::Claude path
# uses Opus 4.7 because that's a one-shot deep summary; chat trades
# depth for latency.
#
# Graceful when ANTHROPIC_API_KEY is unset: .available? returns
# false, the route returns 503, the widget hides itself. Same shape
# as Summarizer::Claude so the two integrations behave consistently.
module Chat
  module Claude
    MODEL              = 'claude-sonnet-4-6'.freeze
    MAX_TOKENS         = 800
    MAX_HISTORY_TURNS  = 8       # last N message pairs we send back to the API
    MAX_CONTEXT_CHARS  = 8_000   # cap the page excerpt so a long article doesn't balloon every request
    MAX_MESSAGE_CHARS  = 4_000   # cap the user's single message

    Result = Struct.new(:status, :text, :model, :error, :usage, keyword_init: true)

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are a helpful AI assistant embedded in Tech Feed Reader, a
      personal RSS / podcast aggregator. The user is currently viewing
      a page; the page's URL, title, and a content excerpt are
      provided below. Use that context to answer questions, summarize,
      pull out key points, or discuss the material conversationally.

      Style: concise, direct, factual. No preamble like "Great
      question!" or "Based on the article…". When the page context is
      empty or unrelated to the user's question, just answer the
      question directly without forcing it.

      Markdown is fine — short bold for emphasis, bullets for lists.
      Do not invent facts that aren't in the page context; if you
      don't know, say so.
    PROMPT

    module_function

    def available?
      !ENV['ANTHROPIC_API_KEY'].to_s.empty?
    end

    # Send the next turn. `message` is the user's new input; `history`
    # is an array of {role:, content:} hashes the widget has accumulated
    # client-side; `context` is { url:, title:, excerpt: }.
    def respond(message:, history: [], context: {})
      unless available?
        return Result.new(status: :unavailable, error: 'ANTHROPIC_API_KEY not set')
      end

      msg = message.to_s.strip
      return Result.new(status: :empty, error: 'empty message') if msg.empty?
      msg = msg[0, MAX_MESSAGE_CHARS]

      ctx_url     = context[:url].to_s
      ctx_title   = context[:title].to_s
      ctx_excerpt = context[:excerpt].to_s[0, MAX_CONTEXT_CHARS]
      system_text = build_system(ctx_url, ctx_title, ctx_excerpt)

      messages = build_messages(history, msg)

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      AppLogger.info('chat_start', model: MODEL, message_chars: msg.length, context_url: ctx_url, history_turns: history.length)

      response = Tracing.in_span(
        'llm.chat',
        attributes: {
          'llm.vendor'         => 'anthropic',
          'llm.model'          => MODEL,
          'llm.input_chars'    => msg.length,
          'llm.history_turns'  => history.length,
          'chat.context_url'   => ctx_url,
          'chat.context_title' => ctx_title
        }
      ) do |span|
        r = client.messages.create(
          model:      MODEL.to_sym,
          max_tokens: MAX_TOKENS,
          system_:    system_text,
          messages:   messages
        )
        if span.respond_to?(:set_attribute) && r.respond_to?(:usage) && r.usage
          span.set_attribute('llm.input_tokens',  r.usage.input_tokens.to_i)
          span.set_attribute('llm.output_tokens', r.usage.output_tokens.to_i)
        end
        r
      end
      latency = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

      text_block = response.content.find { |b| b.type == :text }
      text       = text_block&.text.to_s.strip
      if text.empty?
        AppLogger.warn('chat', status: :error, reason: 'empty response', latency_ms: latency)
        return Result.new(status: :error, error: 'empty response')
      end

      AppLogger.info('chat_done', model: MODEL, latency_ms: latency, output_chars: text.length)
      Metrics::SUMMARIES_GENERATED.increment(labels: { kind: 'chat' })
      Result.new(status: :ok, text: text, model: MODEL, usage: usage_hash(response))
    rescue Anthropic::Errors::APIError => e
      AppLogger.error('chat', status: :error, class: e.class.name, message: e.message)
      Result.new(status: :error, error: "#{e.class.name}: #{e.message}")
    rescue StandardError => e
      AppLogger.error('chat', status: :error, class: e.class.name, message: e.message)
      Result.new(status: :error, error: "#{e.class.name}: #{e.message}")
    end

    class << self
      private

      def client
        @client ||= Anthropic::Client.new
      end
    end

    module_function

    def build_system(url, title, excerpt)
      ctx = +"#{SYSTEM_PROMPT}\n\nCurrent page context:\n"
      ctx << "URL: #{url}\n"     unless url.empty?
      ctx << "Title: #{title}\n" unless title.empty?
      if excerpt.empty?
        ctx << "Excerpt: (no content excerpt available for this page)\n"
      else
        ctx << "Excerpt:\n#{excerpt}\n"
      end
      ctx
    end

    # Trim history to the most recent MAX_HISTORY_TURNS pairs and add
    # the new user message. Skips entries with unknown roles or empty
    # content so a malformed client payload can't poison the request.
    def build_messages(history, new_user_message)
      cleaned = Array(history).each_with_object([]) do |entry, acc|
        role    = entry.is_a?(Hash) ? (entry['role']    || entry[:role]).to_s    : ''
        content = entry.is_a?(Hash) ? (entry['content'] || entry[:content]).to_s : ''
        next unless %w[user assistant].include?(role)
        next if content.strip.empty?
        acc << { role: role, content: content }
      end
      cleaned = cleaned.last(MAX_HISTORY_TURNS * 2)
      cleaned << { role: 'user', content: new_user_message }
      cleaned
    end

    def usage_hash(response)
      return nil unless response.respond_to?(:usage) && response.usage
      {
        input_tokens:  response.usage.input_tokens.to_i,
        output_tokens: response.usage.output_tokens.to_i
      }
    end
  end
end
