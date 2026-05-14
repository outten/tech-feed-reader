require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/read_state_store'

# Phase 4 — passive listened-percent signal. Two surfaces:
#   1. ReadStateStore.mark_passive_feedback   (store-level explicit-wins)
#   2. POST /api/podcasts/:uid/feedback        (JSON route called by the player)

# read_state.article_id has a FK to articles.id with ON DELETE CASCADE
# so we go through ArticlesStore.import to create a real row.
def make_podcast_article(uid: 'passive00001')
  feed = FeedsStore.find_by_url('https://x.com/passive-rss') ||
         FeedsStore.add(url: 'https://x.com/passive-rss', title: 'Passive Feedback Show')
  ArticlesStore.import(feed_id: feed['id'], entries: [{
    uid: uid, title: 'Episode 1', url: "https://x.com/#{uid}", author: nil,
    published_at: '2026-05-06T12:00:00Z',
    content_html: '<p>x</p>', content_text: 'x',
    audio_url: 'https://x.com/audio.mp3', audio_mime_type: 'audio/mpeg',
    audio_duration_seconds: 1800
  }])
  ArticlesStore.find_by_uid(uid)
end

RSpec.describe ReadStateStore, '#mark_passive_feedback (Phase 4)' do
  let(:article) { make_podcast_article }
  let(:article_id) { article['id'] }

  it 'defaults to 0 (no signal) for an article with no row yet' do
    expect(ReadStateStore.get(1, article_id)['passive_feedback']).to eq(0)
  end

  it 'persists +1 (≥80% listened)' do
    ReadStateStore.mark_passive_feedback(1, article_id, value: 1)
    expect(ReadStateStore.get(1, article_id)['passive_feedback']).to eq(1)
  end

  it 'persists -1 (skip)' do
    ReadStateStore.mark_passive_feedback(1, article_id, value: -1)
    expect(ReadStateStore.get(1, article_id)['passive_feedback']).to eq(-1)
  end

  it 'clears via value: 0' do
    ReadStateStore.mark_passive_feedback(1, article_id, value: 1)
    ReadStateStore.mark_passive_feedback(1, article_id, value: 0)
    expect(ReadStateStore.get(1, article_id)['passive_feedback']).to eq(0)
  end

  it 'rejects values outside the {-1, 0, +1} set' do
    expect {
      ReadStateStore.mark_passive_feedback(1, article_id, value: 2)
    }.to raise_error(ArgumentError, /must be -1, 0, or \+1/)
  end

  describe 'explicit-wins guard' do
    it 'is a no-op when explicit feedback is +1 (passive cannot overwrite)' do
      ReadStateStore.mark_feedback(1, article_id, value: 1)
      ReadStateStore.mark_passive_feedback(1, article_id, value: -1)
      row = ReadStateStore.get(1, article_id)
      expect(row['feedback']).to eq(1)
      expect(row['passive_feedback']).to eq(0)
    end

    it 'is a no-op when explicit feedback is -1' do
      ReadStateStore.mark_feedback(1, article_id, value: -1)
      ReadStateStore.mark_passive_feedback(1, article_id, value: 1)
      row = ReadStateStore.get(1, article_id)
      expect(row['feedback']).to eq(-1)
      expect(row['passive_feedback']).to eq(0)
    end

    it 'persists when explicit feedback is 0 (cleared or never set)' do
      ReadStateStore.mark_passive_feedback(1, article_id, value: 1)
      row = ReadStateStore.get(1, article_id)
      expect(row['feedback']).to eq(0)
      expect(row['passive_feedback']).to eq(1)
    end

    it 'persists once, then becomes a no-op when explicit lands later' do
      ReadStateStore.mark_passive_feedback(1, article_id, value: 1)
      expect(ReadStateStore.get(1, article_id)['passive_feedback']).to eq(1)
      ReadStateStore.mark_feedback(1, article_id, value: -1)
      ReadStateStore.mark_passive_feedback(1, article_id, value: 0)
      row = ReadStateStore.get(1, article_id)
      expect(row['feedback']).to eq(-1)
      expect(row['passive_feedback']).to eq(1)  # untouched after explicit
    end
  end

  it 'leaves read / bookmarked / archived / explicit feedback untouched' do
    ReadStateStore.mark_read(1, article_id, read: true)
    ReadStateStore.mark_bookmarked(1, article_id, value: true)
    ReadStateStore.mark_passive_feedback(1, article_id, value: 1)
    row = ReadStateStore.get(1, article_id)
    expect(row['read']).to eq(1)
    expect(row['bookmarked']).to eq(1)
    expect(row['archived']).to eq(0)
    expect(row['feedback']).to eq(0)
    expect(row['passive_feedback']).to eq(1)
  end
end

RSpec.describe 'POST /api/podcasts/:uid/feedback' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  def post_json(path, body)
    post path, body.to_json, { 'CONTENT_TYPE' => 'application/json' }
  end

  it 'persists +1 from a valid JSON body' do
    article = make_podcast_article
    post_json "/api/podcasts/#{article['uid']}/feedback", { signal: 1, listened_pct: 0.92 }
    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)).to include('ok' => true, 'applied' => true, 'explicit_present' => false)
    expect(ReadStateStore.get(1, article['id'])['passive_feedback']).to eq(1)
  end

  it 'persists -1 from a valid JSON body' do
    article = make_podcast_article
    post_json "/api/podcasts/#{article['uid']}/feedback", { signal: -1, listened_pct: 0.04 }
    expect(last_response.status).to eq(200)
    expect(ReadStateStore.get(1, article['id'])['passive_feedback']).to eq(-1)
  end

  it 'reports applied: false + explicit_present: true when explicit feedback already set' do
    article = make_podcast_article
    ReadStateStore.mark_feedback(1, article['id'], value: 1)
    post_json "/api/podcasts/#{article['uid']}/feedback", { signal: -1, listened_pct: 0.05 }
    expect(last_response.status).to eq(200)
    body = JSON.parse(last_response.body)
    expect(body).to include('ok' => true, 'applied' => false, 'explicit_present' => true)
    # And the explicit value is unchanged.
    row = ReadStateStore.get(1, article['id'])
    expect(row['feedback']).to eq(1)
    expect(row['passive_feedback']).to eq(0)
  end

  it '404s on an unknown uid' do
    post_json '/api/podcasts/doesnotexist/feedback', { signal: 1, listened_pct: 1.0 }
    expect(last_response.status).to eq(404)
  end

  it '400s on a missing signal' do
    article = make_podcast_article
    post_json "/api/podcasts/#{article['uid']}/feedback", { listened_pct: 0.5 }
    expect(last_response.status).to eq(400)
  end

  it '400s on a signal outside {-1, 0, +1}' do
    article = make_podcast_article
    post_json "/api/podcasts/#{article['uid']}/feedback", { signal: 7, listened_pct: 1.0 }
    expect(last_response.status).to eq(400)
  end

  it '400s on a malformed JSON body' do
    article = make_podcast_article
    post "/api/podcasts/#{article['uid']}/feedback", '{not json',
         { 'CONTENT_TYPE' => 'application/json' }
    expect(last_response.status).to eq(400)
  end

  it 'returns content_type: application/json on success' do
    article = make_podcast_article
    post_json "/api/podcasts/#{article['uid']}/feedback", { signal: 1, listened_pct: 1.0 }
    expect(last_response.content_type).to include('application/json')
  end
end
