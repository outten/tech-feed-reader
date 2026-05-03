require_relative 'spec_helper'

# `app/sidekiq_boot.rb` is the entry point passed to `bundle exec sidekiq -r`.
# It must (a) load every worker class so jobs can be popped and run, and
# (b) configure Sidekiq with the shared Redis URL. Loading the file in
# the test process is the lightest-weight way to catch typos / require
# paths going stale — we don't actually start the worker.
RSpec.describe 'app/sidekiq_boot.rb' do
  it 'loads cleanly and registers FeedRefreshWorker' do
    expect { load File.expand_path('../app/sidekiq_boot.rb', __dir__) }.not_to raise_error
    expect(defined?(FeedRefreshWorker)).to eq('constant')
  end
end
