require 'webauthn'
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
    /sign-up
    /sign-in
    /sign-out
    /health
    /metrics
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

    def require_signed_in!
      return if signed_in?
      session[:return_to] = request.fullpath if request.get?
      redirect to('/sign-in')
    end

    # Sign-in / sign-out helpers. Always rotate the session on
    # sign-in to prevent fixation; on sign-out clear the whole
    # session so a stale chat-context etc. doesn't leak.
    def sign_in!(user)
      session.clear
      session[:user_id] = user['id'].to_i
      UsersStore.touch_last_seen!(user['id'])
      AppLogger.info('user_signed_in', user_id: user['id'], username: user['username'])
    end

    def sign_out!
      uid = session[:user_id]
      session.clear
      AppLogger.info('user_signed_out', user_id: uid)
    end
  end
end
