require 'anthropic'
require 'json'
require_relative '../logger'

module TriviaGenerator
  MODEL      = 'claude-haiku-4-5-20251001'.freeze
  MAX_TOKENS = 2000
  # Max chars of content_text per article fed to Claude.
  MAX_ARTICLE_CHARS = 800

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are a daily news trivia quiz generator. Given a list of recent news
    articles, generate exactly 5 multiple-choice questions that test real
    comprehension of the day's news — not obscure trivia, but meaningful
    facts a reader would learn from these articles.

    Vary the topics across different articles when possible. Each question
    should have one clearly correct answer and three plausible distractors.

    Return ONLY a JSON array of exactly 5 objects. Each object must have:
      "question"      — the question text (one sentence)
      "a"             — choice A text
      "b"             — choice B text
      "c"             — choice C text
      "d"             — choice D text
      "correct"       — one of: "a", "b", "c", "d"
      "explanation"   — 1–2 sentences explaining why the correct answer is right
      "article_title" — title of the source article
      "article_url"   — URL of the source article

    Do not include any text outside the JSON array.
  PROMPT

  Result = Struct.new(:status, :questions, :model, :error, keyword_init: true)

  module_function

  def available?
    !ENV['ANTHROPIC_API_KEY'].to_s.empty?
  end

  # articles — array of hashes with keys: title, url, content_text (or summary)
  # Returns a Result. On :ok, .questions is an Array of 5 question hashes.
  def generate(articles:)
    unless available?
      AppLogger.warn('trivia_generate', status: :unavailable, reason: 'ANTHROPIC_API_KEY not set')
      return Result.new(status: :unavailable)
    end

    if articles.empty?
      AppLogger.warn('trivia_generate', status: :empty, reason: 'no articles supplied')
      return Result.new(status: :empty)
    end

    context = build_context(articles)
    AppLogger.info('trivia_generate_start', model: MODEL, article_count: articles.length, context_chars: context.length)

    response = client.messages.create(
      model:      MODEL.to_sym,
      max_tokens: MAX_TOKENS,
      system_:    SYSTEM_PROMPT,
      messages:   [{ role: 'user', content: context }]
    )

    raw = response.content.find { |b| b.type == :text }&.text.to_s.strip
    questions = parse_questions(raw)

    if questions.nil? || questions.length < 3
      AppLogger.warn('trivia_generate', status: :parse_error, raw_length: raw.length)
      return Result.new(status: :error, error: 'could not parse questions from response')
    end

    AppLogger.info('trivia_generate_done', model: MODEL, questions: questions.length)
    Result.new(status: :ok, questions: questions, model: MODEL)
  rescue Anthropic::Errors::APIError => e
    AppLogger.error('trivia_generate', status: :error, class: e.class.name, message: e.message)
    Result.new(status: :error, error: "#{e.class.name}: #{e.message}")
  rescue StandardError => e
    AppLogger.error('trivia_generate', status: :error, class: e.class.name, message: e.message)
    Result.new(status: :error, error: "#{e.class.name}: #{e.message}")
  end

  # ── private ───────────────────────────────────────────────────────────────

  def build_context(articles)
    lines = ["Here are today's top news articles:\n"]
    articles.each_with_index do |a, i|
      title   = a['title'].to_s.strip
      url     = a['url'].to_s.strip
      summary = (a['content_text'] || a['summary'] || '').to_s.strip
      summary = summary[0, MAX_ARTICLE_CHARS] + '…' if summary.length > MAX_ARTICLE_CHARS

      lines << "#{i + 1}. #{title}"
      lines << "   URL: #{url}" unless url.empty?
      lines << "   #{summary}" unless summary.empty?
      lines << ''
    end
    lines.join("\n")
  end
  private_class_method :build_context

  REQUIRED_KEYS = %w[question a b c d correct explanation].freeze
  VALID_LETTERS = %w[a b c d].freeze

  def parse_questions(raw)
    # Strip optional markdown code fences
    json_str = raw.gsub(/\A```(?:json)?\s*/i, '').gsub(/\s*```\z/, '').strip
    data     = JSON.parse(json_str)
    return nil unless data.is_a?(Array)

    data.select do |q|
      q.is_a?(Hash) &&
        REQUIRED_KEYS.all? { |k| q[k].is_a?(String) && !q[k].strip.empty? } &&
        VALID_LETTERS.include?(q['correct'].downcase)
    end.map do |q|
      q.merge('correct' => q['correct'].downcase)
    end
  rescue JSON::ParserError
    nil
  end
  private_class_method :parse_questions

  def client
    @client ||= Anthropic::Client.new
  end
  private_class_method :client
end
