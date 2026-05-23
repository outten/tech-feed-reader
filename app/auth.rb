require 'webauthn'
require 'base64'
require 'rack/utils'
require_relative 'users_store'
require_relative 'webauthn_credentials_store'
require_relative 'recovery_codes_store'
require_relative 'logger'

# Phase A1 (consumer auth). One-stop module for:
#
#   • WebAuthn configuration (relying-party id, name, origin)
#   • Session helpers (current_user, signed_in?, require_signed_in!)
#   • The public-path allowlist used by the before-filter in main.rb
#
# Configuration comes from ENV (loaded via dotenv in dev):
#
#   WEBAUTHN_RP_NAME — display name shown in the browser's passkey UI
#   WEBAUTHN_RP_ID   — bare domain ("localhost" in dev, "tfr.example.com" in prod).
#                      The browser binds passkeys to this exact RP ID;
#                      changing it after registration invalidates them.
#   WEBAUTHN_ORIGIN  — full origin including scheme + port
#                      ("http://localhost:4567" in dev). Used to verify
#                      the clientDataJSON origin during the ceremonies.
#   SESSION_SECRET   — 64-byte hex for the signed-cookie session store.
module Auth
  module_function

  # The set of paths that DON'T require a signed-in user. Everything
  # else gets bounced to /sign-in by the before-filter. Static assets
  # served by Sinatra's `:public` are exempt automatically — the filter
  # only runs when a route matches.
  PUBLIC_PATHS = Set.new(%w[
    /
    /about
    /privacy
    /terms
    /contact
    /sign-up
    /sign-in
    /sign-out
    /health
    /metrics
    /robots.txt
    /sitemap.xml
  ]).freeze

  # Path prefixes that don't require auth (more flexible than PUBLIC_PATHS
  # for routes that take a tail like /api/auth/*).
  PUBLIC_PREFIXES = [
    '/api/auth/',
    '/img/'
  ].freeze

  def public_path?(path)
    return true if PUBLIC_PATHS.include?(path)
    PUBLIC_PREFIXES.any? { |p| path.start_with?(p) }
  end

  # STUFF #49 — admin HTTP Basic Auth gate. /admin/* + /api/admin/*
  # are additionally protected by Basic Auth credentials (separate
  # from the WebAuthn sign-in wall — so even a signed-in user must
  # know the admin password). Credentials come from two env vars:
  #
  #   ADMIN_USERNAME=admin
  #   ADMIN_PASSWORD=<long random string>
  #
  # Fail-closed: an unset / empty pair means /admin/* returns 401
  # for everyone (including the operator). Forces an explicit
  # opt-in to admin access rather than a missing-env-var bug
  # silently opening the door.
  #
  # Compared to the obvious alternative ("just allowlist a username
  # from the passkey sign-in"), Basic Auth here:
  #   - Adds a second factor (the admin password) beyond passkey
  #     possession.
  #   - Doesn't require any signed-in user — a stolen passkey alone
  #     can't reach admin pages without the password too.
  #   - Lets us protect /admin from prod even before passkey sign-in
  #     is fully rolled out to a target user.
  ADMIN_PATH_PREFIXES = ['/admin/', '/api/admin/'].freeze
  ADMIN_PATHS         = Set.new(%w[/admin]).freeze

  def admin_credentials
    user = ENV['ADMIN_USERNAME'].to_s
    pass = ENV['ADMIN_PASSWORD'].to_s
    return nil if user.empty? || pass.empty?
    [user, pass]
  end

  # Parse the inbound Authorization header. Returns [user, pass]
  # on success, nil on absent / malformed input. Tolerant of
  # encoding glitches (rescue StandardError) — anything we can't
  # parse falls through to "no credentials" which fails the
  # constant-time compare below.
  def basic_auth_from(env)
    header = env['HTTP_AUTHORIZATION'].to_s
    return nil unless header.start_with?('Basic ')
    decoded = Base64.decode64(header.sub('Basic ', ''))
    user, pass = decoded.split(':', 2)
    [user.to_s, pass.to_s]
  rescue StandardError
    nil
  end

  # True iff the request's Authorization header matches the
  # configured admin credentials. Constant-time compare via
  # Rack::Utils.secure_compare to thwart timing attacks on the
  # username + password.
  def authorized_admin?(env)
    expected = admin_credentials
    return false unless expected
    provided = basic_auth_from(env)
    return false unless provided
    Rack::Utils.secure_compare(expected[0], provided[0]) &&
      Rack::Utils.secure_compare(expected[1], provided[1])
  end

  # Match /admin, /admin/*, /api/admin/* — kept here (not inlined
  # in main.rb) so the test surface can exercise it directly.
  def admin_path?(path)
    return true if ADMIN_PATHS.include?(path)
    ADMIN_PATH_PREFIXES.any? { |p| path.start_with?(p) }
  end

  def configure!
    rp_name = ENV.fetch('WEBAUTHN_RP_NAME', 'Tech Feed Reader')
    rp_id   = ENV.fetch('WEBAUTHN_RP_ID',   'localhost')
    origin  = ENV.fetch('WEBAUTHN_ORIGIN',  'http://localhost:4567')

    WebAuthn.configure do |config|
      config.allowed_origins = [origin]
      config.rp_name = rp_name
      config.rp_id   = rp_id
      # Apple, Google, Microsoft, FIDO2 keys, etc. — accept whatever the
      # client offers. We're verifying possession of the credential, not
      # vouching for the manufacturer.
      config.algorithms = %w[ES256 RS256 EdDSA]
    end

    AppLogger.debug('auth_configure', rp_id: rp_id, origin: origin)
  end

  # Module-level convenience helpers — bound onto Sinatra via `helpers do`
  # in main.rb so the same code is callable from views + routes.
  module Helpers
    def current_user
      return @current_user if defined?(@current_user)
      uid = session[:user_id]
      @current_user = uid ? UsersStore.find(uid) : nil
    end

    def signed_in?
      !current_user.nil?
    end

    # The shorthand routes use to scope per-user store calls. Asserts
    # the request has a signed-in user — if you hit this with nil
    # current_user the before-filter forgot to redirect, which is a
    # programming error. Returns an Integer so DB layer doesn't have to
    # re-coerce.
    def current_user_id
      u = current_user
      raise 'current_user_id called without a signed-in user' unless u
      u['id'].to_i
    end

    def require_signed_in!
      return if signed_in?
      session[:return_to] = request.fullpath if request.get?
      redirect to('/sign-in')
    end

    # STUFF #49 — true when the inbound request carries valid
    # admin Basic Auth credentials. Independent of the signed-in
    # user (admin is a separate password, not just an attribute
    # on the WebAuthn account). Used by the before-filter +
    # available to views if they want to render admin-only nav
    # entries to passing-by users.
    def admin?
      Auth.authorized_admin?(request.env)
    end

    # Sign-in / sign-out helpers. Always rotate the session on
    # sign-in to prevent fixation; on sign-out clear the whole
    # session so a stale chat-context etc. doesn't leak.
    def sign_in!(user)
      session.clear
      session[:user_id] = user['id'].to_i
      UsersStore.touch_last_seen!(user['id'])
      remove_instance_variable(:@current_user) if defined?(@current_user)
      AppLogger.info('user_signed_in', user_id: user['id'], username: user['username'])
    end

    def sign_out!
      uid = session[:user_id]
      session.clear
      remove_instance_variable(:@current_user) if defined?(@current_user)
      AppLogger.info('user_signed_out', user_id: uid)
    end
  end
end
