require_relative 'spec_helper'
require 'set'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/read_state_store'
require_relative '../app/recommendation/for_you'
require_relative '../app/triage/claude'

# Phase S10 — per-topic scoping for the For You ranker + Triage.
# Tech feedback shouldn't influence sports rankings, and vice
# versa. Without scoping, a 👍 on a Eagles article boosts tech
# articles that share words like "draft".

def make_topical(uid:, title:, feed_topic:, feed_url: nil, feed_title: 'Test Feed', content: 'body content')
  feed_url ||= "https://x.com/topical-#{feed_topic}"
  feed = FeedsStore.find_by_url(feed_url) ||
         FeedsStore.add(url: feed_url, title: feed_title, topic: feed_topic)
  ArticlesStore.import(feed_id: feed['id'], entries: [{
    uid: uid, title: title, url: "https://x.com/#{uid}",
    author: nil, published_at: '2026-05-08T12:00:00Z',
    content_html: "<p>#{content}</p>", content_text: content,
    audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
  }])
  ArticlesStore.find_by_uid(uid)
end

RSpec.describe Recommendation::ForYou, '#corpus_terms (Phase S10 topic scoping)' do
  it 'restricts the positive corpus to articles whose feed.topic matches' do
    tech = make_topical(uid: 'tcorp01', title: 'Ruby on Rails performance',
                        feed_topic: 'technology', content: 'ruby rails performance bug')
    sports = make_topical(uid: 'scorp01', title: 'Eagles draft strategy',
                          feed_topic: 'sports', content: 'eagles draft picks rounds')
    ReadStateStore.mark_bookmarked(tech['id'],   value: true)
    ReadStateStore.mark_bookmarked(sports['id'], value: true)

    tech_terms   = Recommendation::ForYou.corpus_terms(positive: true, topic: 'technology')
    sports_terms = Recommendation::ForYou.corpus_terms(positive: true, topic: 'sports')

    expect(tech_terms).to include('ruby').or include('rails')
    expect(tech_terms).not_to include('eagles')
    expect(sports_terms).to include('eagles').or include('draft')
    expect(sports_terms).not_to include('rails')
  end

  it 'unscoped (topic: nil) returns the union — legacy behaviour' do
    make_topical(uid: 'tcorp02', title: 'Ruby T', feed_topic: 'technology', content: 'ruby gem')
    make_topical(uid: 'scorp02', title: 'Eagles S', feed_topic: 'sports',   content: 'eagles touchdown')
    ReadStateStore.mark_bookmarked(ArticlesStore.find_by_uid('tcorp02')['id'], value: true)
    ReadStateStore.mark_bookmarked(ArticlesStore.find_by_uid('scorp02')['id'], value: true)
    terms = Recommendation::ForYou.corpus_terms(positive: true)
    expect(terms.length).to be > 0
    # At least one term from each topic appears (union behaviour).
    cross_topic = terms.intersect?(%w[ruby gem].to_set) && terms.intersect?(%w[eagles touchdown].to_set)
    expect(cross_topic).to be(true)
  end
end

RSpec.describe Recommendation::ForYou, '#score_window (Phase S10 topic scoping)' do
  it 'topic: filters the candidate window' do
    make_topical(uid: 'twin0001', title: 'Tech',   feed_topic: 'technology')
    make_topical(uid: 'swin0001', title: 'Sports', feed_topic: 'sports')

    tech_uids   = Recommendation::ForYou.score_window(state: :all, limit: 50, offset: 0,
                                                        topic: 'technology').map { |a| a['uid'] }
    sports_uids = Recommendation::ForYou.score_window(state: :all, limit: 50, offset: 0,
                                                        topic: 'sports').map { |a| a['uid'] }
    expect(tech_uids).to     include('twin0001')
    expect(tech_uids).not_to include('swin0001')
    expect(sports_uids).to     include('swin0001')
    expect(sports_uids).not_to include('twin0001')
  end
end

RSpec.describe Triage::Claude, '#run (Phase S10 topic scoping)' do
  before do
    ENV['ANTHROPIC_API_KEY'] = 'sk-test-fake-key'
    Triage::Claude.instance_variable_set(:@client, nil)
  end
  after do
    ENV.delete('ANTHROPIC_API_KEY')
    Triage::Claude.instance_variable_set(:@client, nil)
  end

  def stub_claude(json_text)
    block    = double('TextBlock', type: :text, text: json_text)
    response = double('Message', content: [block], usage: nil)
    messages = double('Messages')
    captured_prompt = nil
    allow(messages).to receive(:create) do |args|
      captured_prompt = args[:messages].first[:content]
      response
    end
    allow(Anthropic::Client).to receive(:new).and_return(double('Client', messages: messages))
    -> { captured_prompt }
  end

  it 'restricts unread + corpus to the requested topic' do
    make_topical(uid: 'ttri01', title: 'Tech unread',   feed_topic: 'technology')
    make_topical(uid: 'stri01', title: 'Sports unread', feed_topic: 'sports')

    captured = stub_claude(JSON.generate(must_read: [], optional: [], skip: []))
    Triage::Claude.run(topic: 'sports')
    prompt = captured.call
    expect(prompt).to     include('Sports unread')
    expect(prompt).not_to include('Tech unread')
  end
end

RSpec.describe '/articles?sort=relevance&topic=' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'forwards topic into the For You scorer (renders only matching topic)' do
    make_topical(uid: 'tlist0001', title: 'TechRow',   feed_topic: 'technology')
    make_topical(uid: 'slist0001', title: 'SportsRow', feed_topic: 'sports')

    get '/articles?sort=relevance&topic=sports&state=unread'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to     include('SportsRow')
    expect(last_response.body).not_to include('TechRow')
  end
end

RSpec.describe '/triage topic chip + scoping' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'renders all-topics + per-topic chips at the page header' do
    get '/triage'
    expect(last_response.body).to include('all topics')
    expect(last_response.body).to include('href="/triage?topic=technology"')
    expect(last_response.body).to include('href="/triage?topic=sports"')
  end

  it 'marks the matching topic chip as active' do
    get '/triage?topic=sports'
    expect(last_response.body).to match(%r{class="active"[^>]*>sports}m)
  end

  it 'carries topic into the Generate form when scoped' do
    get '/triage?topic=sports'
    expect(last_response.body).to include('<input type="hidden" name="topic" value="sports">')
  end
end
