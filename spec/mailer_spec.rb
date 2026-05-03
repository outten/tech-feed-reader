require_relative 'spec_helper'
require_relative '../app/mailer'

RSpec.describe Mailer do
  ENV_KEYS = %w[SMTP_HOST SMTP_PORT SMTP_USERNAME SMTP_PASSWORD SMTP_FROM SMTP_STARTTLS SMTP_TLS SMTP_AUTH SMTP_DOMAIN].freeze

  around(:each) do |ex|
    saved = ENV_KEYS.each_with_object({}) { |k, h| h[k] = ENV[k] }
    ENV_KEYS.each { |k| ENV.delete(k) }
    ex.run
  ensure
    ENV_KEYS.each { |k| ENV[k] = saved[k] }
  end

  describe '.configured? / .missing' do
    it 'reports unconfigured when nothing is set' do
      expect(Mailer.configured?).to be(false)
      expect(Mailer.missing).to match_array(Mailer::REQUIRED_ENV)
    end

    it 'reports configured when all required vars are present' do
      ENV['SMTP_HOST']     = 'smtp.example.com'
      ENV['SMTP_PORT']     = '587'
      ENV['SMTP_USERNAME'] = 'user'
      ENV['SMTP_PASSWORD'] = 'pass'
      ENV['SMTP_FROM']     = 'from@example.com'
      expect(Mailer.configured?).to be(true)
      expect(Mailer.missing).to be_empty
    end

    it 'treats whitespace-only env values as missing' do
      Mailer::REQUIRED_ENV.each { |k| ENV[k] = '   ' }
      expect(Mailer.configured?).to be(false)
      expect(Mailer.missing).to match_array(Mailer::REQUIRED_ENV)
    end
  end

  describe '.deliver' do
    def configure_env!
      ENV['SMTP_HOST']     = 'smtp.example.com'
      ENV['SMTP_PORT']     = '587'
      ENV['SMTP_USERNAME'] = 'user'
      ENV['SMTP_PASSWORD'] = 'pass'
      ENV['SMTP_FROM']     = 'from@example.com'
    end

    it 'returns :unconfigured + lists missing env vars when SMTP is not set' do
      result = Mailer.deliver(to: 'to@example.com', subject: 's', text: 'x')
      expect(result.status).to eq(:unconfigured)
      expect(result.error).to include('SMTP_HOST')
    end

    it 'returns :unconfigured when To: is blank, even with SMTP set' do
      configure_env!
      result = Mailer.deliver(to: '   ', subject: 's', text: 'x')
      expect(result.status).to eq(:unconfigured)
      expect(result.error).to include('recipient')
    end

    it 'builds a multipart message and calls deliver! on success' do
      configure_env!
      sent_msg = nil
      allow_any_instance_of(Mail::Message).to receive(:deliver!) do |msg|
        sent_msg = msg
        msg
      end

      result = Mailer.deliver(
        to:      'to@example.com',
        subject: 'Hi',
        text:    'plain body',
        html:    '<p>html body</p>'
      )

      expect(result.status).to eq(:ok)
      expect(sent_msg.to).to eq(['to@example.com'])
      expect(sent_msg.from).to eq(['from@example.com'])
      expect(sent_msg.subject).to eq('Hi')
      expect(sent_msg.text_part.body.to_s).to include('plain body')
      expect(sent_msg.html_part.body.to_s).to include('<p>html body</p>')
    end

    it 'omits the html part when html: is nil' do
      configure_env!
      sent_msg = nil
      allow_any_instance_of(Mail::Message).to receive(:deliver!) do |msg|
        sent_msg = msg
        msg
      end

      Mailer.deliver(to: 'to@example.com', subject: 'Hi', text: 'plain only')
      expect(sent_msg.text_part.body.to_s).to include('plain only')
      expect(sent_msg.html_part).to be_nil
    end

    it 'returns :error (does not raise) when SMTP delivery throws' do
      configure_env!
      allow_any_instance_of(Mail::Message).to receive(:deliver!).and_raise(Net::SMTPAuthenticationError, 'bad creds')

      result = Mailer.deliver(to: 'to@example.com', subject: 's', text: 'x')
      expect(result.status).to eq(:error)
      expect(result.error).to include('bad creds')
    end
  end
end
