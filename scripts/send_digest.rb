#!/usr/bin/env ruby
# Send the daily digest email. Wire-up:
#
#   1. Compose: pull unread articles published in the last DIGEST_WINDOW_HOURS
#      (default 24), join their cached summaries, render text + HTML.
#   2. Deliver: hand off to Mailer (SMTP via env). Recipient is DIGEST_TO.
#
# Idempotent — running it twice in the same day produces (and sends)
# the same digest twice. The intent is one cron / launchd entry per
# day, e.g.:
#
#   # crontab -e — fire every morning at 7am local
#   0 7 * * *  cd /path/to/tech-feed-reader && bundle exec ruby scripts/send_digest.rb >> tmp/logs/digest.log 2>&1
#
# Skip-on-empty: by default we still send a "no new articles" email so
# the user knows the cron is alive. Set DIGEST_SKIP_IF_EMPTY=1 to
# suppress that.
#
# Env (most live in .credentials):
#   SMTP_HOST / SMTP_PORT / SMTP_USERNAME / SMTP_PASSWORD / SMTP_FROM   required
#   DIGEST_TO                                                            required
#   DIGEST_WINDOW_HOURS  default 24
#   DIGEST_LIMIT         default 25
#   DIGEST_SKIP_IF_EMPTY default 0 (send the empty digest)
require_relative '../app/credentials'
require_relative '../app/database'
require_relative '../app/digest'
require_relative '../app/mailer'
require_relative '../app/logger'

window = Integer(ENV.fetch('DIGEST_WINDOW_HOURS', '24'), 10)
limit  = Integer(ENV.fetch('DIGEST_LIMIT',        '25'), 10)
skip_empty = ENV['DIGEST_SKIP_IF_EMPTY'].to_s == '1'
to     = ENV['DIGEST_TO'].to_s.strip

if to.empty?
  warn 'DIGEST_TO is not set. Add it to .credentials and re-run.'
  exit 2
end

result = Digest.compose(window_hours: window, limit: limit)
puts "Composed: #{result.count} unread article(s) in last #{window}h"

if result.count.zero? && skip_empty
  puts 'DIGEST_SKIP_IF_EMPTY=1 — nothing new, not sending.'
  exit 0
end

send = Mailer.deliver(
  to:      to,
  subject: result.subject,
  text:    result.text,
  html:    result.html
)

case send.status
when :ok
  puts "Sent: #{send.message_id}"
  exit 0
when :unconfigured
  warn "Mailer not configured: #{send.error}"
  exit 2
else
  warn "Send failed: #{send.error}"
  exit 1
end
