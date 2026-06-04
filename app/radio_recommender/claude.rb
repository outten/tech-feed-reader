require 'anthropic'
require 'json'
require_relative '../logger'

# Suggests unfollowed radio stations from the catalog based on what
# the user already follows. Uses the catalog as the only source of
# truth — Claude picks from a numbered list, so there are no invented
# URLs or hallucinated stations.
module RadioRecommender
  module Claude
    MODEL      = 'claude-haiku-4-5-20251001'.freeze
    MAX_TOKENS = 800
    MAX_PICKS  = 5

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are a personalized internet radio recommender.

      The user gives you a list of stations they already follow and a
      numbered catalog of stations they have NOT yet followed.

      Your job: pick up to %{max} stations from the catalog that this
      user would likely enjoy, based on their current taste.

      Rules:
      - Only pick stations that appear in the provided catalog list.
        Reference them by their catalog number (e.g. "3").
      - Up to %{max} picks, ordered best-first.
      - Provide a short one-sentence rationale for each pick (why it
        matches their taste).
      - If the user's follow list is empty, suggest broadly popular or
        approachable stations.

      Respond with ONLY a JSON array. Each element must have:
        "number"    — the catalog number as an integer
        "rationale" — one sentence explaining the recommendation

      Do not include any text outside the JSON array.
    PROMPT

    Result = Struct.new(:status, :picks, :error, keyword_init: true)

    module_function

    def available?
      !ENV['ANTHROPIC_API_KEY'].to_s.empty?
    end

    # followed_stations — array of DB rows the user already follows
    # catalog_stations  — array of DB rows the user has NOT followed
    # Returns a Result. On :ok, .picks is an Array of station DB rows.
    def recommend(followed_stations:, catalog_stations:)
      unless available?
        return Result.new(status: :unavailable)
      end

      if catalog_stations.empty?
        return Result.new(status: :empty)
      end

      prompt = build_prompt(followed_stations, catalog_stations)
      AppLogger.info('radio_recommend_start', model: MODEL, catalog_size: catalog_stations.length)

      response = client.messages.create(
        model:      MODEL.to_sym,
        max_tokens: MAX_TOKENS,
        system_:    format(SYSTEM_PROMPT, max: MAX_PICKS),
        messages:   [{ role: 'user', content: prompt }]
      )

      raw   = response.content.find { |b| b.type == :text }&.text.to_s.strip
      picks = parse_picks(raw, catalog_stations)

      AppLogger.info('radio_recommend_done', model: MODEL, picks: picks.length)
      Result.new(status: :ok, picks: picks)
    rescue Anthropic::Errors::APIError => e
      AppLogger.error('radio_recommend', status: :error, message: e.message)
      Result.new(status: :error, error: e.message)
    rescue StandardError => e
      AppLogger.error('radio_recommend', status: :error, message: e.message)
      Result.new(status: :error, error: e.message)
    end

    # ── private ─────────────────────────────────────────────────────────────

    def build_prompt(followed, catalog)
      lines = []

      if followed.empty?
        lines << "I haven't followed any stations yet."
      else
        lines << "Stations I currently follow:"
        followed.each { |s| lines << "  - #{s['name']} (#{s['genre']}) [#{s['catalog']}]" }
      end

      lines << ""
      lines << "Catalog of stations I have NOT yet followed (pick from these):"
      catalog.each_with_index do |s, i|
        lines << "  #{i + 1}. #{s['name']} — #{s['genre']} — #{s['description'].to_s.slice(0, 80)}"
      end

      lines.join("\n")
    end
    private_class_method :build_prompt

    def parse_picks(raw, catalog)
      json_str = raw.gsub(/\A```(?:json)?\s*/i, '').gsub(/\s*```\z/, '').strip
      data     = JSON.parse(json_str)
      return [] unless data.is_a?(Array)

      data.filter_map do |item|
        next unless item.is_a?(Hash)
        idx = item['number'].to_i - 1
        station = catalog[idx]
        next unless station
        station.merge('rationale' => item['rationale'].to_s.strip)
      end.first(MAX_PICKS)
    rescue JSON::ParserError
      []
    end
    private_class_method :parse_picks

    def client
      @client ||= Anthropic::Client.new
    end
    private_class_method :client
  end
end
