require 'mail'
require_relative 'logger'

# Thin wrapper around the `mail` gem. All SMTP details are pulled from
# env vars at delivery time so the worker process / cron job can fail
# loudly with a useful message if anything's missing — no surprise
# silent fallbacks to Sendmail or local-MTA-not-running.
#
# Required env (all in .credentials):
#   SMTP_HOST       e.g. smtp.gmail.com
#   SMTP_PORT       e.g. 587
#   SMTP_USERNAME   account login
#   SMTP_PASSWORD   account password / app-specific password
#   SMTP_FROM       From: header (also used as SMTP MAIL FROM)
#   DIGEST_TO       Recipient — set once, the digest script reads this
#
# Mailer.deliver(to:, subject:, text:, html: nil) returns a Result
# struct so the caller can branch on :ok / :unconfigured / :error
# without rescuing — same shape as Summarizer::Claude / Chat::Claude.
module Mailer
  Result = Struct.new(:status, :message_id, :error, keyword_init: true)

  REQUIRED_ENV = %w[SMTP_HOST SMTP_PORT SMTP_USERNAME SMTP_PASSWORD SMTP_FROM].freeze

  module_function

  def configured?
    missing.empty?
  end

  def missing
    REQUIRED_ENV.reject { |k| ENV[k].to_s.strip.length.positive? }
  end

  def deliver(to:, subject:, text:, html: nil)
    if (gone = missing).any?
      return Result.new(status: :unconfigured, error: "missing env: #{gone.join(', ')}")
    end
    if to.to_s.strip.empty?
      return Result.new(status: :unconfigured, error: 'missing recipient (To:)')
    end

    apply_smtp_defaults!

    msg = Mail.new do
      to       to
      from     ENV['SMTP_FROM']
      subject  subject
      text_part do
        body text
      end
      if html
        html_part do
          content_type 'text/html; charset=UTF-8'
          body html
        end
      end
    end

    AppLogger.info('mailer_send_start',
                   to: to, subject: subject,
                   text_chars: text.to_s.length,
                   html_chars: html.to_s.length,
                   smtp_host: ENV['SMTP_HOST'])
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    msg.deliver!
    latency = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    AppLogger.info('mailer_send_done', to: to, latency_ms: latency, message_id: msg.message_id)

    Result.new(status: :ok, message_id: msg.message_id)
  rescue StandardError => e
    AppLogger.error('mailer_send_error', to: to, class: e.class.name, message: e.message)
    Result.new(status: :error, error: "#{e.class.name}: #{e.message}")
  end

  class << self
    private

    # Apply SMTP defaults to the global Mail config. Idempotent — re-runs
    # cheap and the gem just overwrites the previous config. Pulled out
    # of deliver so a future test can stub it.
    def apply_smtp_defaults!
      port      = Integer(ENV.fetch('SMTP_PORT'), 10)
      starttls  = ENV['SMTP_STARTTLS'].to_s.strip.downcase != 'false'    # default on
      tls_mode  = ENV['SMTP_TLS'].to_s.strip.downcase == 'true'          # default off (use STARTTLS)
      auth      = ENV['SMTP_AUTH'] || 'plain'
      domain    = ENV['SMTP_DOMAIN'] || ENV['SMTP_FROM'].to_s.split('@').last
      Mail.defaults do
        delivery_method :smtp,
          address:              ENV['SMTP_HOST'],
          port:                 port,
          user_name:            ENV['SMTP_USERNAME'],
          password:             ENV['SMTP_PASSWORD'],
          authentication:       auth.to_sym,
          enable_starttls_auto: starttls,
          tls:                  tls_mode,
          domain:               domain
      end
    end
  end
end
