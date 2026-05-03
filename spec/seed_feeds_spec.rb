require_relative 'spec_helper'
require_relative '../app/feeds_store'

# The seed script writes to FeedsStore at load time, so we exercise it
# by `load`-ing the file inside a hermetic in-memory DB. It defines a
# top-level constant SEED_FEEDS that we can also assert against.
RSpec.describe 'scripts/seed_feeds.rb' do
  let(:script_path) { File.expand_path('../../scripts/seed_feeds.rb', __FILE__) }

  it 'seeds the kickoff feed list (5 RSS + 3 podcasts)' do
    expect { silence_stdout { load(script_path) } }
      .to change { FeedsStore.count }.from(0).to(8)

    titles = FeedsStore.all.map { |f| f['title'] }
    expect(titles).to contain_exactly(
      'Hacker News', 'Lobsters', 'Ars Technica', 'The Verge', 'Simon Willison',
      'The Changelog', 'Software Engineering Daily', 'Latent Space'
    )
  end

  it 'is idempotent — a second run adds zero feeds' do
    silence_stdout { load(script_path) }
    expect { silence_stdout { load(script_path) } }.not_to(change { FeedsStore.count })
  end

  def silence_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end
end
