require_relative 'spec_helper'

# Regression for the Sidekiq Cron web tab (/admin/sidekiq/cron) raising
#   NoMethodError: undefined method 'configuration' for module Sidekiq::Cron
# when rendered. Sidekiq::Cron::Job#initialize calls Sidekiq::Cron.configuration,
# which is DEFINED + initialized only by the full 'sidekiq-cron' require
# (lib/sidekiq/cron.rb). `sidekiq/cron/web` alone loads job.rb (which CALLS it)
# but not the file that defines it — so the server boot block must require
# 'sidekiq-cron' before mounting the Cron tab. The worker is fine because
# sidekiq_boot.rb already requires 'sidekiq-cron'.
RSpec.describe 'Sidekiq Cron web tab boot dependency' do
  let(:boot) do
    src = File.read(File.expand_path('../app/main.rb', __dir__))
    src[/if __FILE__ == \$PROGRAM_NAME.*\z/m] or raise 'server boot block not found in app/main.rb'
  end

  it "requires the full 'sidekiq-cron' gem before mounting the Cron web tab" do
    full = boot.index("require 'sidekiq-cron'")
    web  = boot.index("require 'sidekiq/cron/web'")
    expect(full).not_to be_nil, "boot block must require 'sidekiq-cron' — the Cron tab needs Sidekiq::Cron.configuration"
    expect(web).not_to be_nil
    expect(full).to be < web
  end

  it 'Sidekiq::Cron.configuration is available once the full gem is required' do
    require 'sidekiq-cron'
    require 'sidekiq/cron/web'
    expect(Sidekiq::Cron).to respond_to(:configuration)
    expect(Sidekiq::Cron.configuration).not_to be_nil
  end
end
