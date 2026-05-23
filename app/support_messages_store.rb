require_relative 'database'

# STUFF #62 — read/write surface for the /contact form + /admin/support
# queue. Thin — the admin queue is the operator's tool, no per-user
# scoping is needed (operator sees everything).
module SupportMessagesStore
  module_function

  STATUSES        = %w[new reviewed responded].freeze
  SUBJECT_MAX     = 200
  BODY_MAX        = 5_000
  REPLY_TO_MAX    = 200
  ADMIN_NOTE_MAX  = 5_000

  def db; Database.connection; end

  # subject + reply_to are optional; body is required. Caller has
  # already trimmed lengths to the maxes above.
  def create!(user_id:, subject:, body:, reply_to:)
    row = db.execute(<<~SQL, [user_id, subject, body, reply_to]).first
      INSERT INTO support_messages (user_id, subject, body, reply_to)
      VALUES (?, ?, ?, ?)
      RETURNING *
    SQL
    row
  end

  def find(id)
    db.execute('SELECT * FROM support_messages WHERE id = ?', [id.to_i]).first
  end

  # Admin queue. Newest-first; optional status filter.
  def list(status: nil, limit: 200)
    if status && !status.to_s.empty?
      db.execute(<<~SQL, [status.to_s, limit])
        SELECT * FROM support_messages
        WHERE status = ?
        ORDER BY created_at DESC
        LIMIT ?
      SQL
    else
      db.execute(<<~SQL, [limit])
        SELECT * FROM support_messages
        ORDER BY created_at DESC
        LIMIT ?
      SQL
    end
  end

  def count_by_status
    rows = db.execute('SELECT status, COUNT(*) AS c FROM support_messages GROUP BY status')
    rows.each_with_object(Hash.new(0)) { |r, h| h[r['status']] = r['c'].to_i }
  end

  def update!(id, status: nil, admin_note: nil)
    fields = []
    args   = []
    if status && STATUSES.include?(status.to_s)
      fields << 'status = ?'; args << status.to_s
    end
    unless admin_note.nil?
      fields << 'admin_note = ?'; args << admin_note.to_s
    end
    return false if fields.empty?
    fields << 'updated_at = NOW()'
    args   << id.to_i
    db.execute("UPDATE support_messages SET #{fields.join(', ')} WHERE id = ?", args)
    true
  end
end
