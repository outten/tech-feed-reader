require_relative 'spec_helper'
require_relative '../app/pruner'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/read_state_store'
require_relative '../app/summary_store'
require_relative '../app/tags_store'

RSpec.describe Pruner do
  let(:now) { Time.utc(2026, 5, 5, 12, 0, 0) }
  let(:feed) { FeedsStore.add(url: 'https://x.com/rss', title: 'Example') }

  def add(uid:, title:, days_ago: nil, published_at: nil, fetched_at: nil)
    pub = published_at
    pub ||= days_ago && (now - days_ago * 86_400).iso8601
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: uid, title: title,
      url: "https://x.com/#{uid}", author: nil,
      published_at: pub,
      content_html: '<p>x</p>', content_text: 'x',
      audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
    }])
    row = ArticlesStore.find_by_uid(uid)
    if fetched_at
      Database.connection.execute('UPDATE articles SET fetched_at = ? WHERE id = ?', [fetched_at, row['id']])
    end
    row
  end

  describe '.prune_old' do
    it 'returns a zero-count result when nothing is past the window' do
      add(uid: 'fresharticle', title: 'Fresh', days_ago: 1)
      result = Pruner.prune_old(now: now)
      expect(result.deleted).to eq(0)
      expect(result.kept_bookmarked).to eq(0)
      expect(result.cutoff).to eq((now - 7 * 86_400).iso8601)
      expect(result.retention_days).to eq(Pruner::DEFAULT_RETENTION_DAYS)
    end

    it 'deletes articles whose published_at is older than the retention window' do
      add(uid: 'old1old1old1', title: 'Old',   days_ago: 10)
      add(uid: 'newrnewrnewr', title: 'New',   days_ago: 1)
      result = Pruner.prune_old(now: now)
      expect(result.deleted).to eq(1)
      expect(ArticlesStore.find_by_uid('old1old1old1')).to be_nil
      expect(ArticlesStore.find_by_uid('newrnewrnewr')).not_to be_nil
    end

    it 'preserves bookmarked articles past the window' do
      old = add(uid: 'oldbookmrkbk', title: 'Old + bookmarked', days_ago: 30)
      add(uid: 'oldarticleab', title: 'Old, unread', days_ago: 30)
      ReadStateStore.mark_bookmarked(1, old['id'], value: true)

      result = Pruner.prune_old(now: now)
      expect(result.deleted).to eq(1)
      expect(result.kept_bookmarked).to eq(1)
      expect(ArticlesStore.find_by_uid('oldbookmrkbk')).not_to be_nil
      expect(ArticlesStore.find_by_uid('oldarticleab')).to be_nil
    end

    it 'with keep_unread:true, also preserves unread articles past the window' do
      add(uid: 'oldunread011', title: 'Old + unread', days_ago: 30)
      old_read = add(uid: 'oldreadthis1', title: 'Old + read', days_ago: 30)
      ReadStateStore.mark_read(1, old_read['id'], read: true)

      result = Pruner.prune_old(keep_unread: true, now: now)
      expect(result.deleted).to eq(1)             # only the read one
      expect(result.kept_unread).to eq(1)
      expect(ArticlesStore.find_by_uid('oldunread011')).not_to be_nil
      expect(ArticlesStore.find_by_uid('oldreadthis1')).to be_nil
    end

    it 'falls back to fetched_at when published_at is null' do
      old_fetch = (now - 30 * 86_400).iso8601
      add(uid: 'nopubd000001', title: 'No publish date — old fetch', published_at: nil, fetched_at: old_fetch)
      add(uid: 'nopubd000002', title: 'No publish date — fresh fetch', published_at: nil, fetched_at: now.iso8601)

      result = Pruner.prune_old(now: now)
      expect(result.deleted).to eq(1)
      expect(ArticlesStore.find_by_uid('nopubd000001')).to be_nil
      expect(ArticlesStore.find_by_uid('nopubd000002')).not_to be_nil
    end

    it 'honours a custom retention_days argument' do
      add(uid: 'olda22000001', title: '5 days old',  days_ago: 5)
      add(uid: 'oldb22000002', title: '10 days old', days_ago: 10)
      result = Pruner.prune_old(retention_days: 3, now: now)
      expect(result.deleted).to eq(2)
      expect(result.retention_days).to eq(3)
    end

    it 'cascades through read_state / summaries / article_tags / articles_fts' do
      old = add(uid: 'oldwithdeps1', title: 'Old + deps', days_ago: 30)
      tag = TagsStore.add(user_id: 1, name: 'tag1', match_kind: 'keyword', match_value: 'foo')
      TagsStore.tag_article(old['id'], tag['id'])
      SummaryStore.upsert(old['id'], extractive: 'old summary', llm: 'old llm', llm_model: 'claude-x')
      ReadStateStore.mark_read(1, old['id'], read: true)

      Pruner.prune_old(now: now)

      db = Database.connection
      expect(db.execute('SELECT COUNT(*) AS c FROM articles      WHERE id = ?', [old['id']]).first['c']).to eq(0)
      expect(db.execute('SELECT COUNT(*) AS c FROM read_state    WHERE article_id = ?', [old['id']]).first['c']).to eq(0)
      expect(db.execute('SELECT COUNT(*) AS c FROM summaries     WHERE article_id = ?', [old['id']]).first['c']).to eq(0)
      expect(db.execute('SELECT COUNT(*) AS c FROM article_tags  WHERE article_id = ?', [old['id']]).first['c']).to eq(0)
      # FTS5 trigger keeps articles_fts in sync — the rowid should be gone too.
      # SQLite-only: PG uses a tsvector column on articles itself (no
      # separate index table to sync), so the cascade above already
      # covers the search-index removal on the PG path.
      if Database.adapter == :sqlite
        fts_rows = db.execute('SELECT rowid FROM articles_fts WHERE rowid = ?', [old['id']])
        expect(fts_rows).to be_empty
      end
    end

    it 'still deletes archived articles past the window (archived is not a protection signal)' do
      old = add(uid: 'oldarchived1', title: 'Old + archived', days_ago: 30)
      ReadStateStore.mark_archived(1, old['id'], value: true)
      result = Pruner.prune_old(now: now)
      expect(result.deleted).to eq(1)
      expect(ArticlesStore.find_by_uid('oldarchived1')).to be_nil
    end

    it 'is idempotent — a second run with no new old articles deletes nothing' do
      add(uid: 'oldarticleab', title: 'Old', days_ago: 30)
      first  = Pruner.prune_old(now: now)
      second = Pruner.prune_old(now: now)
      expect(first.deleted).to eq(1)
      expect(second.deleted).to eq(0)
    end
  end
end
