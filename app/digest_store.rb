require_relative 'database'

# Per-user persistence for the digest feature. One row per digest run,
# keyed by (user_id, generated_at); #recent lists newest-first for the
# /digests UI, #find loads a single row for /digests/:id.
module DigestStore
  module_function

  def db
    Database.connection
  end

  def create(user_id, digest)
    sql = <<~SQL
      INSERT INTO digests (user_id, generated_at, window_hours, article_count,
                           subject, text_body, html_body)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    SQL
    db.execute(sql, [
      user_id.to_i,
      digest.generated_at.iso8601,
      digest.window_hours,
      digest.count,
      digest.subject,
      digest.text,
      digest.html
    ])
    db.last_insert_row_id
  end

  def recent(user_id, limit: 50)
    db.execute(<<~SQL, [user_id.to_i, limit])
      SELECT id, generated_at, window_hours, article_count, subject
      FROM digests
      WHERE user_id = ?
      ORDER BY generated_at DESC, id DESC
      LIMIT ?
    SQL
  end

  def find(user_id, id)
    db.execute('SELECT * FROM digests WHERE user_id = ? AND id = ?', [user_id.to_i, id.to_i]).first
  end

  def count(user_id)
    db.execute('SELECT COUNT(*) AS c FROM digests WHERE user_id = ?', [user_id.to_i]).first['c']
  end

  def update_llm_summary(user_id, id, summary:, model:, generated_at: Time.now.utc.iso8601)
    db.execute(<<~SQL, [summary.to_s, model.to_s, generated_at, user_id.to_i, id.to_i])
      UPDATE digests
      SET llm_summary       = ?,
          llm_model         = ?,
          llm_generated_at  = ?
      WHERE user_id = ? AND id = ?
    SQL
    db.changes
  end
end
