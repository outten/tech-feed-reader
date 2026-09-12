require 'openssl'
require 'securerandom'
require_relative 'database'
require_relative 'users_store'

# ios-app change — bearer tokens for native clients. Issued alongside
# the existing WebAuthn ceremonies (register/login/recovery) when the
# request signals a native client; browser cookie-session auth is
# untouched. Only the HMAC hash is stored, never the plaintext — same
# approach as RecoveryCodesStore, reusing SESSION_SECRET as the HMAC key
# so we don't introduce a second secret.
module ApiTokensStore
  module_function

  def db
    Database.connection
  end

  def hash_token(token)
    key = ENV['SESSION_SECRET'].to_s
    raise 'SESSION_SECRET not set — refusing to hash API tokens with an empty key' if key.empty?
    OpenSSL::HMAC.hexdigest('SHA256', key, token.to_s)
  end

  # Mint + store a fresh token for user_id, return the plaintext. The
  # plaintext is shown to the caller exactly once (in the ceremony's
  # JSON response) — there's no way to retrieve it again.
  def issue!(user_id)
    token = "tfr_#{SecureRandom.hex(32)}"
    db.execute(
      'INSERT INTO api_tokens (user_id, token_hash) VALUES (?, ?)',
      [user_id.to_i, hash_token(token)]
    )
    token
  end

  # Returns the owning user's row for a valid, presented plaintext
  # token, or nil if it doesn't match any issued token. Bumps
  # last_used_at on success.
  def find_user_by_token(plaintext)
    return nil if plaintext.to_s.empty?
    row = db.execute(
      'SELECT user_id FROM api_tokens WHERE token_hash = ?',
      [hash_token(plaintext)]
    ).first
    return nil unless row
    db.execute(
      'UPDATE api_tokens SET last_used_at = ? WHERE token_hash = ?',
      [Time.now.utc.strftime('%Y-%m-%d %H:%M:%S'), hash_token(plaintext)]
    )
    UsersStore.find(row['user_id'])
  end

  # Revoke (delete) a presented token — used by sign-out. Returns true
  # if a row was actually deleted.
  def revoke!(plaintext)
    return false if plaintext.to_s.empty?
    db.execute('DELETE FROM api_tokens WHERE token_hash = ?', [hash_token(plaintext)])
    db.changes.positive?
  end
end
