require_relative 'spec_helper'
require_relative '../app/digest_store'
require_relative '../app/digests'

RSpec.describe DigestStore do
  def make_result(generated_at:, count: 5, window_hours: 24, subject: 'Subj', text: 'TEXT', html: '<div>HTML</div>')
    Digests::Result.new(
      subject: subject, text: text, html: html, count: count,
      window_hours: window_hours, generated_at: generated_at
    )
  end

  it 'starts with an empty digests table' do
    expect(DigestStore.count(1)).to eq(0)
    expect(DigestStore.recent(1)).to eq([])
  end

  it 'persists every column on .create and returns the new row id' do
    res = make_result(generated_at: Time.utc(2026, 5, 4, 7, 0, 0))
    id  = DigestStore.create(1, res)
    expect(id).to be > 0

    row = DigestStore.find(1, id)
    expect(row['subject']).to eq('Subj')
    expect(row['text_body']).to eq('TEXT')
    expect(row['html_body']).to eq('<div>HTML</div>')
    expect(row['article_count']).to eq(5)
    expect(row['window_hours']).to eq(24)
    expect(row['generated_at']).to eq('2026-05-04T07:00:00Z')
  end

  it 'lists rows newest-first via .recent' do
    DigestStore.create(1, make_result(generated_at: Time.utc(2026, 5, 1, 7, 0, 0), subject: 'oldest'))
    DigestStore.create(1, make_result(generated_at: Time.utc(2026, 5, 4, 7, 0, 0), subject: 'newest'))
    DigestStore.create(1, make_result(generated_at: Time.utc(2026, 5, 2, 7, 0, 0), subject: 'middle'))

    subjects = DigestStore.recent(1).map { |r| r['subject'] }
    expect(subjects).to eq(%w[newest middle oldest])
  end

  it 'honours the limit kwarg on .recent' do
    5.times { |i| DigestStore.create(1, make_result(generated_at: Time.utc(2026, 5, i + 1, 7, 0, 0))) }
    expect(DigestStore.recent(1, limit: 2).length).to eq(2)
  end

  it '.find returns nil for unknown id' do
    expect(DigestStore.find(1, 99_999)).to be_nil
  end
end
