require 'json'
require_relative 'database'

# Persistence layer for Triage::Claude.run results. Mirrors
# DigestStore: one row per generated triage, browseable at
# /triage/:id, listable at /triage. Cron entry point is
# scripts/generate_triage.rb (`make triage`).
#
# Stores the three groups as JSON arrays so the schema doesn't have
# to change every time the prompt evolves to add a new field per
# entry. Reading hides the JSON behind .find — callers see plain
# Ruby arrays of hashes.
module TriageStore
  module_function

  def db
    Database.connection
  end

  # Persist a Triage::Claude::Result. Returns the new row id. Inputs
  # come straight off the Result struct so the script entry point
  # and the route handler don't have to massage the shape.
  def create(result)
    sql = <<~SQL
      INSERT INTO triages (
        generated_at, unread_count, model,
        must_read, optional, skip,
        status, error, latency_ms,
        input_tokens, output_tokens, topic, raw
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    SQL
    db.execute(sql, [
      Time.now.utc.iso8601,
      result.unread_count.to_i,
      result.model.to_s,
      JSON.generate(Array(result.must_read)),
      JSON.generate(Array(result.optional)),
      JSON.generate(Array(result.skip)),
      result.status.to_s,
      result.error,
      result.latency_ms,
      result.input_tokens,
      result.output_tokens,
      result.respond_to?(:topic) ? result.topic : nil,
      result.respond_to?(:raw) ? result.raw : nil
    ])
    db.last_insert_row_id
  end

  # Most recent triages, listing fields only (no body parse). Used by
  # the /triage list view at the bottom of the manual-trigger page.
  # Phase S10 follow-up — when topic: is passed, filters to runs
  # generated for that scope (NULL topic = cross-topic legacy run).
  def recent(limit: 20, topic: :any)
    if topic == :any
      db.execute(<<~SQL, [limit])
        SELECT id, generated_at, unread_count, status, model, topic
        FROM triages
        ORDER BY generated_at DESC, id DESC
        LIMIT ?
      SQL
    elsif topic.nil?
      db.execute(<<~SQL, [limit])
        SELECT id, generated_at, unread_count, status, model, topic
        FROM triages
        WHERE topic IS NULL
        ORDER BY generated_at DESC, id DESC
        LIMIT ?
      SQL
    else
      db.execute(<<~SQL, [topic.to_s, limit])
        SELECT id, generated_at, unread_count, status, model, topic
        FROM triages
        WHERE topic = ?
        ORDER BY generated_at DESC, id DESC
        LIMIT ?
      SQL
    end
  end

  # Single row by id. JSON-encoded group columns are decoded into
  # arrays here so the view doesn't have to know the storage shape.
  # Returns nil when the id doesn't exist.
  def find(id)
    row = db.execute('SELECT * FROM triages WHERE id = ?', [id.to_i]).first
    return nil unless row
    %w[must_read optional skip].each do |key|
      row[key] = parse_json(row[key])
    end
    row
  end

  def latest
    row = db.execute(<<~SQL).first
      SELECT * FROM triages ORDER BY generated_at DESC, id DESC LIMIT 1
    SQL
    return nil unless row
    %w[must_read optional skip].each do |key|
      row[key] = parse_json(row[key])
    end
    row
  end

  def count
    db.execute('SELECT COUNT(*) AS c FROM triages').first['c']
  end

  class << self
    private

    def parse_json(s)
      return [] if s.to_s.strip.empty?
      JSON.parse(s)
    rescue JSON::ParserError
      []
    end
  end
end
