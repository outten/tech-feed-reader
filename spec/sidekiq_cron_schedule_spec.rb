require_relative 'spec_helper'
require 'yaml'

# Schedule file is loaded by sidekiq_boot.rb in the worker process. We
# can't exercise the real load (would need Redis + Sidekiq.configure_server),
# but we can lock the YAML's shape so a typo here doesn't silently
# disable hourly feed refreshes or nightly sports sync in production.
RSpec.describe 'config/sidekiq_cron.yml' do
  let(:path) { File.expand_path('../config/sidekiq_cron.yml', __dir__) }
  let(:schedule) { YAML.safe_load(File.read(path), aliases: true) }

  it 'parses as YAML and is non-empty' do
    expect(schedule).to be_a(Hash)
    expect(schedule).not_to be_empty
  end

  it 'registers the hourly feed refresh job' do
    expect(schedule).to have_key('refresh_all_feeds')
    job = schedule['refresh_all_feeds']
    expect(job['class']).to eq('RefreshAllFeedsWorker')
    expect(job['cron']).to eq('0 * * * *')
  end

  it 'registers the nightly sports sync job' do
    expect(schedule).to have_key('sports_sync')
    job = schedule['sports_sync']
    expect(job['class']).to eq('SportsSyncWorker')
    expect(job['cron']).to eq('0 4 * * *')
  end

  it 'every job names a class that resolves at load time' do
    require_relative '../app/workers/refresh_all_feeds_worker'
    require_relative '../app/workers/sports_sync_worker'

    schedule.each do |name, job|
      klass_name = job['class']
      expect { Object.const_get(klass_name) }.not_to raise_error,
        "#{name} → class '#{klass_name}' does not resolve"
    end
  end
end
