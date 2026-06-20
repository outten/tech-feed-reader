require 'net/http'
require 'uri'
require_relative 'cache'
require_relative 'logger'

# Operational push alerts (pre-launch). POSTs a short
# message to an ntfy topic (https://ntfy.sh or a self-hosted ntfy) when
# something needs the operator's attention: an unhandled HTTP 500, a dead
# Sidekiq job, or a failed periodic health check. Subscribe to the topic
# in the ntfy phone app to get a push.
#
# Config:
#   NTFY_URL = full topic URL, e.g. https://ntfy.sh/feeder-ops-<random-slug>
#   Unset / blank → no-op (the alert is logged at warn instead, so dev /
#   test / CI never push).
#
# Contract: alerting must NEVER raise into the caller — it runs from error
# paths and from inside jobs, so a wedged ntfy or Redis can't be allowed to
# cascade. Every failure is swallowed + logged. Pushes are rate-limited per
# `dedupe_key` via Redis so one recurring fault can't spam the phone.
module Notifier
  module_function

  PRIORITIES = %w[min low default high urgent].freeze

  def push(title:, body:, tags: [], priority: 'default', dedupe_key: nil, dedupe_ttl: 900)
    url = ENV['NTFY_URL'].to_s.strip
    if url.empty?
      AppLogger.warn('notifier_unconfigured', title: title, body: body.to_s[0, 200])
      return false
    end

    return false if deduped?(dedupe_key, dedupe_ttl)

    post(url, title, body, Array(tags), priority)
    true
  rescue StandardError => e
    AppLogger.error('notifier_failed', title: title, message: e.message)
    false
  end

  # True (and consumes the slot) when `key` already fired within `ttl`.
  # Redis `SET key 1 NX EX ttl` is the lock: it returns 'OK' only when it
  # actually set the key (first time in the window) → not deduped. On any
  # Redis error, treat as not-deduped — better to over-alert than to go dark.
  def deduped?(key, ttl)
    return false if key.nil? || key.to_s.empty?
    Cache.client.call('SET', "alert:#{key}", '1', 'NX', 'EX', ttl) != 'OK'
  rescue StandardError
    false
  end

  def post(url, title, body, tags, priority)
    uri  = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl     = uri.scheme == 'https'
    http.open_timeout = 3
    http.read_timeout = 5

    req = Net::HTTP::Post.new(uri.request_uri)
    req.body      = body.to_s
    req['Title']  = title.to_s
    req['Priority'] = priority.to_s if PRIORITIES.include?(priority.to_s)
    req['Tags']   = tags.join(',') unless tags.empty?
    http.request(req)
  end
end
