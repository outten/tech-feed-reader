require_relative 'database'

# Phase A1 (consumer auth). Wrapper around `webauthn_credentials`.
# Multi-credential per user is supported from day one (so a user can
# add their phone + laptop as separate passkeys).
#
# credential_id + public_key come straight from the WebAuthn server
# library's verification result. We store them as the library
# encodes them (base64url) so we can round-trip without re-parsing.
module WebauthnCredentialsStore
  module_function

  def db
    Database.connection
  end

  def for_user(user_id)
    db.execute(
      'SELECT * FROM webauthn_credentials WHERE user_id = ? ORDER BY created_at',
      [user_id.to_i]
    )
  end

  def find_by_credential_id(credential_id)
    db.execute(
      'SELECT * FROM webauthn_credentials WHERE credential_id = ?',
      [credential_id.to_s]
    ).first
  end

  # Insert a new credential for a user. credential_id + public_key
  # are passed in already-encoded (base64url strings). transports is
  # the AuthenticatorTransport array the browser optionally sent —
  # comma-joined for storage.
  def register!(user_id:, credential_id:, public_key:, sign_count:, transports: nil, label: nil)
    args = [user_id.to_i, credential_id.to_s, public_key.to_s,
            sign_count.to_i, Array(transports).join(','), label]
    db.execute(<<~SQL, args)
      INSERT INTO webauthn_credentials
        (user_id, credential_id, public_key, sign_count, transports, label)
      VALUES (?, ?, ?, ?, ?, ?)
    SQL
    db.last_insert_row_id
  end

  # Update sign_count + last_used_at after a successful authentication.
  # The WebAuthn lib already enforced "new count > old count" before
  # we get here; we just persist the bump.
  def bump_sign_count!(credential_id, new_count)
    db.execute(
      'UPDATE webauthn_credentials SET sign_count = ?, last_used_at = datetime(?) WHERE credential_id = ?',
      [new_count.to_i, Time.now.utc.strftime('%Y-%m-%d %H:%M:%S'), credential_id.to_s]
    )
  end

  def count_for_user(user_id)
    db.execute(
      'SELECT COUNT(*) AS c FROM webauthn_credentials WHERE user_id = ?',
      [user_id.to_i]
    ).first['c']
  end

  # STUFF #29 follow-up — revoke a single passkey from the signed-in
  # user's account. Scoped to (user_id, credential_id) so an attacker
  # who guesses someone else's credential_id can't delete it. Returns
  # true if a row was deleted, false otherwise.
  def delete_for_user!(user_id, credential_id)
    db.execute(
      'DELETE FROM webauthn_credentials WHERE user_id = ? AND credential_id = ?',
      [user_id.to_i, credential_id.to_s]
    )
    db.changes.positive?
  end
end
