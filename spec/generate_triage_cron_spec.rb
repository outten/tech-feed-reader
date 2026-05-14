require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/triage/claude'
require_relative '../app/triage_store'

# Phase S10 follow-up — the daily cron loops over [nil, 'technology',
# 'sports'] and persists one TriageStore row per topic. Verifies that
# the script's three-pass loop works without fork-execing.

def make_topical_for_cron(uid:, title:, feed_topic:, feed_url:)
  feed = FeedsStore.find_by_url(feed_url) ||
         FeedsStore.add(url: feed_url, title: 'Cron Spec Feed', topic: feed_topic)
  ArticlesStore.import(feed_id: feed['id'], entries: [{
    uid: uid, title: title, url: "https://x.com/#{uid}",
    author: nil, published_at: '2026-05-08T12:00:00Z',
    content_html: "<p>#{title}</p>", content_text: title,
    audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
  }])
end

RSpec.describe 'scripts/generate_triage.rb multi-topic loop' do
  before do
    ENV['ANTHROPIC_API_KEY'] = 'sk-test-fake-key'
    Triage::Claude.instance_variable_set(:@client, nil)

    # One unread article per topic so the runs aren't all :empty.
    make_topical_for_cron(uid: 'cron_t01', title: 'Tech unread', feed_topic: 'technology',
                          feed_url: 'https://x.com/cron-tech')
    make_topical_for_cron(uid: 'cron_s01', title: 'Sports unread', feed_topic: 'sports',
                          feed_url: 'https://x.com/cron-sports')
  end

  after do
    ENV.delete('ANTHROPIC_API_KEY')
    Triage::Claude.instance_variable_set(:@client, nil)
  end

  def stub_claude_ok
    block    = double('TextBlock', type: :text, text: JSON.generate(must_read: [], optional: [], skip: []))
    response = double('Message', content: [block], usage: nil)
    messages = double('Messages')
    allow(messages).to receive(:create).and_return(response)
    allow(Anthropic::Client).to receive(:new).and_return(double('Client', messages: messages))
  end

  it 'persists one row per topic in TRIAGE_TOPICS' do
    stub_claude_ok
    expect {
      [nil, 'technology', 'sports'].each do |topic|
        result = Triage::Claude.run(1, topic: topic)
        TriageStore.create(1, result)
      end
    }.to change { TriageStore.count(1) }.by(3)

    topics = TriageStore.recent(1).map { |r| r['topic'] }
    expect(topics).to contain_exactly(nil, 'technology', 'sports')
  end

  it 'TRIAGE_TOPICS constant in the cron script covers cross + tech + sports' do
    src = File.read(File.expand_path('../scripts/generate_triage.rb', __dir__))
    expect(src).to match(/TRIAGE_TOPICS\s*=\s*\[nil,\s*['"]technology['"],\s*['"]sports['"]\]/)
  end
end
