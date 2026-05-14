require 'json'
require_relative 'database'

# Per-user persistence layer for Triage::Claude.run results. Mirrors
# DigestStore: one row per generated triage, browseable at
# /triage/:id, listable at /triage.
#
# Stores the three groups as JSON arrays so the schema doesn't have
# to change every time the prompt evolves. Reading hides the JSON
# behind .find — callers see plain Ruby arrays of hashes.
module TriageStore
  module_function

  def db
    Database.connection
  end

  # Persist a Triage::Claude::Result. Returns the new row id.
  # Accepts (user_id, result) OR (result) — the legacy single-arg form
  # defaults user_id to 1 so pre-A2 specs keep passing.
  def create(*args)
    user_id, result = args.length == 2 ? args : [1, args.first]
    sql = <<~SQL
      INSERT INTO triages (
        user_id, generated_at, unread_count, model,
        must_read, optional, skip,
        status, error, latency_ms,
        input_tokens, output_tokens, topic, raw
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    SQL
    db.execute(sql, [
      user_id.to_i,
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

  # Most recent triages for `user_id`, listing fields only. When
  # topic: is passed, filters to runs generated for that scope
  # (NULL topic = cross-topic legacy run).
  def recent(user_id = 1, limit: 20, topic: :any)
    base_sql = <<~SQL
      SELECT id, generated_at, unread_count, status, model, topic
      FROM triages
      WHERE user_id = ?
    SQL

    if topic == :any
      db.execute("#{base_sql} ORDER BY generated_at DESC, id DESC LIMIT ?", [user_id.to_i, limit])
    elsif topic.nil?
      db.execute("#{base_sql} AND topic IS NULL ORDER BY generated_at DESC, id DESC LIMIT ?", [user_id.to_i, limit])
    else
      db.execute("#{base_sql} AND topic = ? ORDER BY generated_at DESC, id DESC LIMIT ?", [user_id.to_i, topic.to_s, limit])
    end
  end

  # Single row by id, scoped to user. JSON-encoded group columns are
  # decoded into arrays here.
  def find(*args)
    user_id, id = args.length == 2 ? args : [1, args.first]
    row = db.execute('SELECT * FROM triages WHERE user_id = ? AND id = ?', [user_id.to_i, id.to_i]).first
    return nil unless row
    %w[must_read optional skip].each do |key|
      row[key] = parse_json(row[key])
    end
    row
  end

  def latest(user_id = 1)
    row = db.execute(<<~SQL, [user_id.to_i]).first
      SELECT * FROM triages WHERE user_id = ? ORDER BY generated_at DESC, id DESC LIMIT 1
    SQL
    return nil unless row
    %w[must_read optional skip].each do |key|
      row[key] = parse_json(row[key])
    end
    row
  end

  def count(user_id = 1)
    db.execute('SELECT COUNT(*) AS c FROM triages WHERE user_id = ?', [user_id.to_i]).first['c']
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
