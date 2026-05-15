require 'openssl'
require 'securerandom'
require_relative 'database'

# Phase A1 (consumer auth). One-time recovery codes — the escape
# hatch when a user has lost all passkeys + platform sync.
#
# Codes are minted as 5 groups of 4 base32 chars (e.g. "XK4P-9MWZ-..."),
# 20 base32 chars total ≈ 100 bits of entropy. We never store the
# plaintext — only HMAC-SHA256(code, SESSION_SECRET). Not bcrypt:
# codes are high-entropy + single-use, so slow-hashing doesn't earn
# anything and would make recovery feel sluggish.
module RecoveryCodesStore
  CODE_GROUPS      = 5
  GROUP_LENGTH     = 4
  CODES_PER_USER   = 10
  BASE32_ALPHABET  = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'.freeze   # Crockford-ish: no I/L/O/0/1

  module_function

  def db
    Database.connection
  end

  # Returns the HMAC-SHA256 of `code` keyed by SESSION_SECRET. The
  # WebAuthn ceremony also reads SESSION_SECRET, so we don't introduce
  # a second secret just for recovery hashes.
  def hash_code(code)
    key = ENV['SESSION_SECRET'].to_s
    raise 'SESSION_SECRET not set — refusing to hash recovery codes with an empty key' if key.empty?
    OpenSSL::HMAC.hexdigest('SHA256', key, code.to_s)
  end

  # Generate one fresh plaintext code in the public "XK4P-9MWZ-..."
  # format. Each char is a random pick from BASE32_ALPHABET so the
  # entropy is ~5 bits per char × 20 chars = 100 bits.
  def generate_plaintext
    groups = Array.new(CODE_GROUPS) do
      Array.new(GROUP_LENGTH) { BASE32_ALPHABET[SecureRandom.random_number(BASE32_ALPHABET.length)] }.join
    end
    groups.join('-')
  end

  # Mint N codes for a user, store their hashes, return the plaintexts
  # to the caller. Caller renders them ONCE on the post-signup screen;
  # there's no way to retrieve them later by design.
  def mint_for!(user_id:, n: CODES_PER_USER)
    plaintexts = Array.new(n) { generate_plaintext }
    db.transaction do
      plaintexts.each do |code|
        db.execute(
          'INSERT INTO recovery_codes (user_id, code_hash) VALUES (?, ?)',
          [user_id.to_i, hash_code(code)]
        )
      end
    end
    plaintexts
  end

  # Consume a code: returns the user_id on success, nil on a
  # bad/expired/already-used code. Normalizes input by stripping
  # whitespace + uppercasing (so the user pasting "xk4p 9mwz" works).
  def consume!(plaintext)
    normalized = plaintext.to_s.gsub(/\s+/, '').upcase
    return nil if normalized.empty?

    row = db.execute(
      'SELECT id, user_id, consumed_at FROM recovery_codes WHERE code_hash = ?',
      [hash_code(normalized)]
    ).first
    return nil unless row
    return nil if row['consumed_at']  # already used — pretend it doesn't exist

    db.execute(
      'UPDATE recovery_codes SET consumed_at = datetime(?) WHERE id = ?',
      [Time.now.utc.strftime('%Y-%m-%d %H:%M:%S'), row['id']]
    )
    row['user_id']
  end

  def unconsumed_count_for(user_id)
    db.execute(
      'SELECT COUNT(*) AS c FROM recovery_codes WHERE user_id = ? AND consumed_at IS NULL',
      [user_id.to_i]
    ).first['c']
  end

  # STUFF #29 follow-up — wipe every existing code (consumed or not)
  # and mint a fresh batch. Returns the new plaintexts so the caller
  # can render them once on the account page. Atomic so a partial
  # failure can't leave the user with zero codes AND no fresh batch.
  def regenerate_for!(user_id)
    db.transaction do
      db.execute('DELETE FROM recovery_codes WHERE user_id = ?', [user_id.to_i])
    end
    mint_for!(user_id: user_id)
  end
end
