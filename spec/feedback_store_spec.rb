require_relative 'spec_helper'
require_relative '../app/read_state_store'
require_relative '../app/feed_feedback_store'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'

# read_state.article_id has a FK to articles.id with ON DELETE CASCADE,
# so the feedback specs need a real article row to point at.
def make_article(uid: 'rsfeedback01')
  feed = FeedsStore.find_by_url('https://x.com/rsfeedback') ||
         FeedsStore.add(url: 'https://x.com/rsfeedback', title: 'Feedback Spec Feed')
  ArticlesStore.import(feed_id: feed['id'], entries: [{
    uid: uid, title: 'A', url: "https://x.com/#{uid}", author: nil,
    published_at: '2026-05-05T12:00:00Z',
    content_html: '<p>x</p>', content_text: 'x',
    audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
  }])
  ArticlesStore.find_by_uid(uid)['id']
end

RSpec.describe ReadStateStore, '#mark_feedback (Phase 3)' do
  let(:article_id) { make_article }

  it 'defaults to 0 (no signal) for an article with no row yet' do
    expect(ReadStateStore.get(article_id)['feedback']).to eq(0)
  end

  it 'persists +1 (👍) and reads back correctly' do
    ReadStateStore.mark_feedback(article_id, value: 1)
    expect(ReadStateStore.get(article_id)['feedback']).to eq(1)
  end

  it 'persists -1 (👎) and reads back correctly' do
    ReadStateStore.mark_feedback(article_id, value: -1)
    expect(ReadStateStore.get(article_id)['feedback']).to eq(-1)
  end

  it 'clears via value: 0' do
    ReadStateStore.mark_feedback(article_id, value: 1)
    ReadStateStore.mark_feedback(article_id, value: 0)
    expect(ReadStateStore.get(article_id)['feedback']).to eq(0)
  end

  it 'rejects values outside the {-1, 0, +1} set' do
    expect {
      ReadStateStore.mark_feedback(article_id, value: 2)
    }.to raise_error(ArgumentError, /must be -1, 0, or \+1/)
  end

  it 'leaves read / bookmarked / archived untouched when only feedback is set' do
    ReadStateStore.mark_read(article_id, read: true)
    ReadStateStore.mark_bookmarked(article_id, value: true)
    ReadStateStore.mark_feedback(article_id, value: -1)

    row = ReadStateStore.get(article_id)
    expect(row['read']).to       eq(1)
    expect(row['bookmarked']).to eq(1)
    expect(row['archived']).to   eq(0)
    expect(row['feedback']).to   eq(-1)
  end

  it 'is idempotent — same value twice yields the same end state' do
    ReadStateStore.mark_feedback(article_id, value: 1)
    ReadStateStore.mark_feedback(article_id, value: 1)
    expect(ReadStateStore.get(article_id)['feedback']).to eq(1)
  end
end

RSpec.describe FeedFeedbackStore do
  let(:feed)  { FeedsStore.add(url: 'https://x.com/rss', title: 'Example') }
  let(:other) { FeedsStore.add(url: 'https://y.com/rss', title: 'Other') }

  describe '.weight_for' do
    it 'returns DEFAULT_WEIGHT (1.0) when no row exists' do
      expect(FeedFeedbackStore.weight_for(feed['id'])).to eq(1.0)
    end

    it 'returns the stored weight after a bump' do
      FeedFeedbackStore.bump(feed['id'], direction: :up)
      expect(FeedFeedbackStore.weight_for(feed['id'])).to eq(1.25)
    end
  end

  describe '.bump :up' do
    it 'adds STEP per call' do
      expect(FeedFeedbackStore.bump(feed['id'], direction: :up)).to eq(1.25)
      expect(FeedFeedbackStore.bump(feed['id'], direction: :up)).to eq(1.5)
      expect(FeedFeedbackStore.bump(feed['id'], direction: :up)).to eq(1.75)
    end

    it 'clamps at CEILING (3.0)' do
      20.times { FeedFeedbackStore.bump(feed['id'], direction: :up) }
      expect(FeedFeedbackStore.weight_for(feed['id'])).to eq(FeedFeedbackStore::CEILING)
    end
  end

  describe '.bump :down' do
    it 'subtracts STEP per call' do
      expect(FeedFeedbackStore.bump(feed['id'], direction: :down)).to eq(0.75)
      expect(FeedFeedbackStore.bump(feed['id'], direction: :down)).to eq(0.5)
    end

    it 'clamps at FLOOR (0.25) — never goes to zero' do
      20.times { FeedFeedbackStore.bump(feed['id'], direction: :down) }
      expect(FeedFeedbackStore.weight_for(feed['id'])).to eq(FeedFeedbackStore::FLOOR)
    end
  end

  describe '.bump :reset' do
    it 'deletes the row and returns DEFAULT_WEIGHT' do
      FeedFeedbackStore.bump(feed['id'], direction: :up)
      FeedFeedbackStore.bump(feed['id'], direction: :up)
      expect(FeedFeedbackStore.count).to eq(1)

      result = FeedFeedbackStore.bump(feed['id'], direction: :reset)
      expect(result).to eq(1.0)
      expect(FeedFeedbackStore.count).to eq(0)
      expect(FeedFeedbackStore.weight_for(feed['id'])).to eq(1.0)
    end

    it 'is a no-op if no row exists' do
      result = FeedFeedbackStore.bump(feed['id'], direction: :reset)
      expect(result).to eq(1.0)
      expect(FeedFeedbackStore.count).to eq(0)
    end
  end

  describe '.bump validation' do
    it 'rejects unknown directions' do
      expect {
        FeedFeedbackStore.bump(feed['id'], direction: :sideways)
      }.to raise_error(ArgumentError, /direction must be/)
    end
  end

  describe '.weights_by_feed_id' do
    it 'returns DEFAULT_WEIGHT for every requested id when no rows exist' do
      result = FeedFeedbackStore.weights_by_feed_id([feed['id'], other['id']])
      expect(result).to eq(feed['id'] => 1.0, other['id'] => 1.0)
    end

    it 'mixes stored + default weights in one batch lookup' do
      FeedFeedbackStore.bump(feed['id'],  direction: :up)
      FeedFeedbackStore.bump(feed['id'],  direction: :up)
      FeedFeedbackStore.bump(other['id'], direction: :down)

      result = FeedFeedbackStore.weights_by_feed_id([feed['id'], other['id'], 99_999])
      expect(result[feed['id']]).to  eq(1.5)
      expect(result[other['id']]).to eq(0.75)
      expect(result[99_999]).to      eq(1.0)  # unknown id → default
    end

    it 'returns an empty hash for an empty / nil input' do
      expect(FeedFeedbackStore.weights_by_feed_id([])).to eq({})
      expect(FeedFeedbackStore.weights_by_feed_id(nil)).to eq({})
    end
  end

  describe 'cascade behavior' do
    it 'drops the feedback row when the feed is removed (FK ON DELETE CASCADE)' do
      FeedFeedbackStore.bump(feed['id'], direction: :up)
      expect(FeedFeedbackStore.count).to eq(1)

      FeedsStore.remove(feed['id'])
      expect(FeedFeedbackStore.count).to eq(0)
    end
  end
end
