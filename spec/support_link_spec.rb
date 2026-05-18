require_relative 'spec_helper'
require_relative '../app/main'

# STUFF #42.1 — footer "☕ Support" link gated on BMC_HANDLE env.
# Unset (default in dev/test) → link doesn't render. Set →
# renders a link to https://buymeacoffee.com/<handle> in a new tab.
RSpec.describe 'Footer support link (STUFF #42.1)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  around do |ex|
    prior = ENV.fetch('BMC_HANDLE', nil)
    ex.run
  ensure
    if prior
      ENV['BMC_HANDLE'] = prior
    else
      ENV.delete('BMC_HANDLE')
    end
  end

  context 'when BMC_HANDLE is unset' do
    before { ENV.delete('BMC_HANDLE') }

    it 'does NOT render the Support link' do
      get '/about'
      expect(last_response.status).to eq(200)
      expect(last_response.body).not_to include('buymeacoffee.com')
      expect(last_response.body).not_to include('☕ Support')
    end
  end

  context 'when BMC_HANDLE is set to an empty string' do
    before { ENV['BMC_HANDLE'] = '' }

    it 'does NOT render the link (empty string treated as absent)' do
      get '/about'
      expect(last_response.body).not_to include('buymeacoffee.com')
    end
  end

  context 'when BMC_HANDLE is set to a handle' do
    before { ENV['BMC_HANDLE'] = 'tmoney' }

    it 'renders a link to https://buymeacoffee.com/<handle> opening in a new tab' do
      get '/about'
      expect(last_response.body).to match(
        %r{<a href="https://www\.buymeacoffee\.com/tmoney"[^>]*target="_blank"[^>]*rel="noopener noreferrer"[^>]*>☕ Support</a>}
      )
    end

    it 'also renders on /feeds (footer is layout-wide)' do
      get '/feeds'
      expect(last_response.body).to include('https://www.buymeacoffee.com/tmoney')
    end
  end
end
