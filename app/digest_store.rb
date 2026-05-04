require_relative 'database'

# Persistence for the digest feature. One row per digest run, keyed
# by generated_at; #recent lists newest-first for the /digests UI,
# #find loads a single row for /digests/:id.
#
# Bodies are stored as opaque text — the composer (app/digests.rb)
# decides what shape they take. The HTML body is rendered inline in
# the article-detail view so it must be a fragment that fits inside
# the layout's <main> (no <html>, <head>, <body> wrappers).
module DigestStore
  module_function

  def db
    Database.connection
  end

  def create(digest)
    sql = <<~SQL
      INSERT INTO digests (generated_at, window_hours, article_count,
                           subject, text_body, html_body)
      VALUES (?, ?, ?, ?, ?, ?)
    SQL
    db.execute(sql, [
      digest.generated_at.iso8601,
      digest.window_hours,
      digest.count,
      digest.subject,
      digest.text,
      digest.html
    ])
    db.last_insert_row_id
  end

  def recent(limit: 50)
    db.execute(<<~SQL, [limit])
      SELECT id, generated_at, window_hours, article_count, subject
      FROM digests
      ORDER BY generated_at DESC, id DESC
      LIMIT ?
    SQL
  end

  def find(id)
    row = db.execute('SELECT * FROM digests WHERE id = ?', [id.to_i]).first
    row
  end

  def count
    db.execute('SELECT COUNT(*) AS c FROM digests').first['c']
  end
end
