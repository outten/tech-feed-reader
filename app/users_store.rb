require_relative 'database'

# Phase A1 (consumer auth). Wrapper around the `users` table.
# Username is the canonical identity — case-insensitive, lowercased
# at the write boundary so the unique index stays simple. No email,
# no password, no phone. Identity is proven via WebauthnCredentialsStore
# + RecoveryCodesStore.
module UsersStore
  USERNAME_PATTERN = /\A[a-z0-9_-]{3,32}\z/
  USERNAME_RULE    = 'Username must be 3–32 chars: lowercase letters, digits, underscore, or hyphen.'.freeze

  InvalidUsername = Class.new(ArgumentError)

  module_function

  def db
    Database.connection
  end

  def normalize_username(raw)
    raw.to_s.strip.downcase
  end

  def valid_username?(raw)
    USERNAME_PATTERN.match?(normalize_username(raw))
  end

  def find(id)
    db.execute('SELECT * FROM users WHERE id = ?', [id.to_i]).first
  end

  def find_by_username(raw)
    db.execute('SELECT * FROM users WHERE username = ?', [normalize_username(raw)]).first
  end

  def count
    db.execute('SELECT COUNT(*) AS c FROM users').first['c']
  end

  # Creates a row, returning it. Raises InvalidUsername on a bad
  # username; SQLite3::ConstraintException on a duplicate (callers
  # render a "taken" message). display_name defaults to the username
  # itself; the user can leave it blank at signup.
  def create(username:, display_name: nil)
    norm = normalize_username(username)
    raise InvalidUsername, USERNAME_RULE unless USERNAME_PATTERN.match?(norm)

    db.execute(
      'INSERT INTO users (username, display_name) VALUES (?, ?)',
      [norm, display_name.to_s.strip.empty? ? norm : display_name.to_s.strip]
    )
    find(db.last_insert_row_id)
  end

  def touch_last_seen!(id)
    db.execute('UPDATE users SET last_seen_at = datetime(?) WHERE id = ?',
               [Time.now.utc.strftime('%Y-%m-%d %H:%M:%S'), id.to_i])
  end

  # STUFF #29 follow-up — let a signed-in user edit their display name.
  # Display name is free-form (any unicode); we strip + cap length. An
  # empty string falls back to the username so the header chip never
  # renders blank.
  MAX_DISPLAY_NAME = 80

  def update_display_name!(id, display_name)
    user = find(id)
    return nil unless user
    clean = display_name.to_s.strip
    clean = clean[0, MAX_DISPLAY_NAME]
    clean = user['username'] if clean.empty?
    db.execute('UPDATE users SET display_name = ? WHERE id = ?', [clean, id.to_i])
    find(id)
  end

  # STUFF #29 follow-up — account deletion. Per-user tables defined in
  # migration 022 (read_state, feed_feedback, mute_rules, tags,
  # sports_follows, triages, digests, user_feed_subscriptions) all
  # carry `ON DELETE CASCADE` references back to users, so a single
  # DELETE here wipes every trace of the user. The shared `feeds`
  # catalog rows stay (other subscribers may still rely on them).
  def delete!(id)
    db.execute('DELETE FROM users WHERE id = ?', [id.to_i])
    db.changes.positive?
  end
end
