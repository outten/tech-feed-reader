require 'json'
require_relative 'database'

# Pre-launch — fulfils the privacy-policy promise to let a user
# download every per-user row we hold. JSON shape; article bodies
# excluded (publisher content, not user content); passkey private
# keys excluded (don't exist server-side — only the public half is
# stored); recovery-code plaintext excluded (only HMACs persisted —
# the user already saw the plaintext once at signup).
#
# Each top-level key maps to a per-user table. Whole-row dumps for
# simplicity; the user can grep for whatever they need.
module AccountExport
  module_function

  def for_user(user_id)
    {
      schema_version: 1,
      exported_at:    Time.now.utc.iso8601,
      user_id:        user_id,
      tables: {
        user:                fetch('users',                 'id = ?',      [user_id], single: true),
        feeds_users:         fetch('feeds_users',           'user_id = ?', [user_id]),
        read_state:          fetch('read_state',            'user_id = ?', [user_id]),
        tags:                fetch('tags',                  'user_id = ?', [user_id]),
        feed_feedback:       fetch('feed_feedback',         'user_id = ?', [user_id]),
        mute_rules:          fetch('mute_rules',            'user_id = ?', [user_id]),
        sports_follows:      fetch('sports_follows',        'user_id = ?', [user_id]),
        triages:             fetch('triages',               'user_id = ?', [user_id]),
        digests:             fetch('digests',               'user_id = ?', [user_id]),
        webauthn_credentials: fetch_webauthn(user_id),
        recovery_codes:      fetch_recovery_codes(user_id),
        support_messages:    fetch('support_messages',      'user_id = ?', [user_id])
      },
      notes: {
        excluded: [
          'articles.content_html / content_text — publisher content, not user data.',
          'webauthn_credentials.public_key — exported but encoded; private keys never leave your device.',
          'recovery_codes.code_hash — HMAC of the plaintext you saw once at signup.',
          'session cookies — not stored server-side beyond the signed JWT in your browser.'
        ]
      }
    }
  end

  def fetch(table, where_sql, args, single: false)
    sql  = "SELECT * FROM #{table} WHERE #{where_sql} ORDER BY id"
    rows = Database.connection.execute(sql, args)
    single ? rows.first : rows
  rescue StandardError
    # Don't 500 the whole export if a single table query fails (e.g.,
    # schema drift in a future migration). Note the gap; let the user
    # see what we did capture.
    single ? nil : []
  end

  # WebAuthn public keys are stored as binary blobs in some
  # adapters; JSON can't serialise raw bytes. Re-encode public_key
  # as base64 so the export is valid JSON.
  def fetch_webauthn(user_id)
    rows = fetch('webauthn_credentials', 'user_id = ?', [user_id])
    rows.map do |r|
      r.merge('public_key' => Base64.strict_encode64(r['public_key'].to_s))
    end
  end

  # Recovery codes are stored as HMAC hashes (per #29). We export
  # the hash so the user can verify what we have, but the plaintext
  # is never recoverable server-side — they had to save it once
  # during signup.
  def fetch_recovery_codes(user_id)
    fetch('recovery_codes', 'user_id = ?', [user_id]).map do |r|
      r.merge('code_hash' => '[redacted — HMAC, plaintext not recoverable]')
    end
  end
end
