require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/mute_rules_store'

# Phase 5 — mute filters. Three layers:
#   1. MuteRulesStore (CRUD + validation)
#   2. ArticlesStore.state_query NOT EXISTS clause (the actual hide)
#   3. /mutes routes

def make_mute_article(uid:, title: 'A title', author: nil, content_text: 'body content', feed_url: 'https://x.com/mute-rss', feed_title: 'Mute Test Feed')
  feed = FeedsStore.find_by_url(feed_url) || FeedsStore.add(url: feed_url, title: feed_title)
  ArticlesStore.import(feed_id: feed['id'], entries: [{
    uid: uid, title: title, url: "https://x.com/#{uid}",
    author: author, published_at: '2026-05-06T12:00:00Z',
    content_html: "<p>#{content_text}</p>", content_text: content_text,
    audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
  }])
  [feed, ArticlesStore.find_by_uid(uid)]
end

RSpec.describe MuteRulesStore do
  describe '.add' do
    it 'inserts a new rule and returns true' do
      expect(MuteRulesStore.add(user_id: 1, kind: 'keyword', value: 'crypto')).to eq(true)
      expect(MuteRulesStore.count(1)).to eq(1)
    end

    it 'is idempotent — re-adding the same rule returns false (no-op)' do
      MuteRulesStore.add(user_id: 1, kind: 'keyword', value: 'crypto')
      expect(MuteRulesStore.add(user_id: 1, kind: 'keyword', value: 'crypto')).to eq(false)
      expect(MuteRulesStore.count(1)).to eq(1)
    end

    it 'trims surrounding whitespace on value (so "  Hacker News " == "Hacker News")' do
      MuteRulesStore.add(user_id: 1, kind: 'author', value: '  Hacker News ')
      expect(MuteRulesStore.add(user_id: 1, kind: 'author', value: 'Hacker News')).to eq(false)
      expect(MuteRulesStore.count(1)).to eq(1)
    end

    it 'rejects unknown kind' do
      expect { MuteRulesStore.add(user_id: 1, kind: 'sideways', value: 'x') }
        .to raise_error(ArgumentError, /unknown kind/)
    end

    it 'rejects empty value' do
      expect { MuteRulesStore.add(user_id: 1, kind: 'keyword', value: '   ') }
        .to raise_error(ArgumentError, /value must be non-empty/)
    end

    it 'allows the same value across different kinds (composite key)' do
      MuteRulesStore.add(user_id: 1, kind: 'keyword', value: 'foo')
      MuteRulesStore.add(user_id: 1, kind: 'author',  value: 'foo')
      expect(MuteRulesStore.count(1)).to eq(2)
    end
  end

  describe '.remove' do
    it 'deletes a matching rule and returns 1' do
      MuteRulesStore.add(user_id: 1, kind: 'keyword', value: 'crypto')
      expect(MuteRulesStore.remove(user_id: 1, kind: 'keyword', value: 'crypto')).to eq(1)
      expect(MuteRulesStore.count(1)).to eq(0)
    end

    it 'returns 0 when no rule matches' do
      expect(MuteRulesStore.remove(user_id: 1, kind: 'keyword', value: 'nope')).to eq(0)
    end

    it 'rejects unknown kind' do
      expect { MuteRulesStore.remove(user_id: 1, kind: 'sideways', value: 'x') }
        .to raise_error(ArgumentError, /unknown kind/)
    end
  end

  describe '.all + .for_kind' do
    it 'returns rules grouped / filtered correctly' do
      MuteRulesStore.add(user_id: 1, kind: 'keyword', value: 'crypto')
      MuteRulesStore.add(user_id: 1, kind: 'keyword', value: 'web3')
      MuteRulesStore.add(user_id: 1, kind: 'author',  value: 'Spam McSpamface')

      expect(MuteRulesStore.all(1).length).to eq(3)
      expect(MuteRulesStore.for_kind(1, 'keyword').map { |r| r['value'] }).to contain_exactly('crypto', 'web3')
      expect(MuteRulesStore.for_kind(1, 'author').length).to eq(1)
    end
  end
end

RSpec.describe ArticlesStore, 'mute filter (Phase 5)' do
  it 'hides keyword-matching articles from .recent' do
    make_mute_article(uid: 'mute00000001', title: 'A piece on crypto markets')
    make_mute_article(uid: 'mute00000002', title: 'A piece on Rails routing')

    expect(ArticlesStore.recent(1).map { |a| a['uid'] }).to contain_exactly('mute00000001', 'mute00000002')

    MuteRulesStore.add(user_id: 1, kind: 'keyword', value: 'crypto')
    expect(ArticlesStore.recent(1).map { |a| a['uid'] }).to contain_exactly('mute00000002')
  end

  it 'matches keyword against content_text too, not just the title' do
    make_mute_article(uid: 'mute00000003', title: 'Innocuous title', content_text: 'But the body talks all about crypto stuff')
    MuteRulesStore.add(user_id: 1, kind: 'keyword', value: 'crypto')
    expect(ArticlesStore.recent(1).map { |a| a['uid'] }).not_to include('mute00000003')
  end

  it 'is case-insensitive (LOWER() on both sides of LIKE)' do
    make_mute_article(uid: 'mute00000004', title: 'ALL CAPS CRYPTO PIECE')
    MuteRulesStore.add(user_id: 1, kind: 'keyword', value: 'crypto')
    expect(ArticlesStore.recent(1).map { |a| a['uid'] }).not_to include('mute00000004')
  end

  it 'hides author-matching articles' do
    make_mute_article(uid: 'mute00000005', title: 'Title A', author: 'Spam McSpamface')
    make_mute_article(uid: 'mute00000006', title: 'Title B', author: 'Cory Doctorow')
    MuteRulesStore.add(user_id: 1, kind: 'author', value: 'Spam McSpamface')

    expect(ArticlesStore.recent(1).map { |a| a['uid'] }).to contain_exactly('mute00000006')
  end

  it 'author match is exact (not substring)' do
    make_mute_article(uid: 'mute00000007', title: 'Title C', author: 'Spam McSpamface, Jr.')
    MuteRulesStore.add(user_id: 1, kind: 'author', value: 'Spam McSpamface')
    # Different author string ⇒ should still surface.
    expect(ArticlesStore.recent(1).map { |a| a['uid'] }).to include('mute00000007')
  end

  it 'hides feed-matching articles' do
    feed_a, _ = make_mute_article(uid: 'mute00000008', title: 'A', feed_url: 'https://a.example/rss', feed_title: 'A Feed')
    _,      _ = make_mute_article(uid: 'mute00000009', title: 'B', feed_url: 'https://b.example/rss', feed_title: 'B Feed')

    MuteRulesStore.add(user_id: 1, kind: 'feed', value: feed_a['id'].to_s)
    uids = ArticlesStore.recent(1).map { |a| a['uid'] }
    expect(uids).to     include('mute00000009')
    expect(uids).not_to include('mute00000008')
  end

  it 'still surfaces muted articles via .search (FTS5 — bypasses state_query)' do
    make_mute_article(uid: 'mute00000010', title: 'A piece on crypto markets', content_text: 'body about crypto')
    MuteRulesStore.add(user_id: 1, kind: 'keyword', value: 'crypto')

    expect(ArticlesStore.recent(1).map { |a| a['uid'] }).not_to include('mute00000010')
    expect(ArticlesStore.search(1, 'crypto').map { |a| a['uid'] }).to include('mute00000010')
  end

  it 'is a no-op when no rules exist (no perf or behavior regression)' do
    make_mute_article(uid: 'mute00000011', title: 'Anything goes')
    expect(MuteRulesStore.count(1)).to eq(0)
    expect(ArticlesStore.recent(1).map { |a| a['uid'] }).to include('mute00000011')
  end
end

RSpec.describe 'mute routes' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  describe 'POST /mutes' do
    it 'adds a rule and redirects with mute-added notice' do
      post '/mutes', { kind: 'keyword', value: 'crypto' }
      expect(last_response.status).to eq(302)
      expect(last_response.location).to include('notice=mute-added')
      expect(MuteRulesStore.count(1)).to eq(1)
    end

    it 'reports duplicate via the redirect notice' do
      MuteRulesStore.add(user_id: 1, kind: 'keyword', value: 'crypto')
      post '/mutes', { kind: 'keyword', value: 'crypto' }
      expect(last_response.location).to include('notice=mute-duplicate')
    end

    it '400s on an unknown kind' do
      post '/mutes', { kind: 'sideways', value: 'x' }
      expect(last_response.status).to eq(400)
    end

    it '400s on an empty value' do
      post '/mutes', { kind: 'keyword', value: '   ' }
      expect(last_response.status).to eq(400)
    end

    it 'honours return_to' do
      post '/mutes', { kind: 'keyword', value: 'crypto', return_to: '/articles' }
      expect(last_response.location).to end_with('/articles')
    end
  end

  describe 'POST /mutes/delete' do
    it 'removes a rule and redirects with mute-removed notice' do
      MuteRulesStore.add(user_id: 1, kind: 'keyword', value: 'crypto')
      post '/mutes/delete', { kind: 'keyword', value: 'crypto' }
      expect(last_response.status).to eq(302)
      expect(last_response.location).to include('notice=mute-removed')
      expect(MuteRulesStore.count(1)).to eq(0)
    end

    it 'reports not-found via the notice when the rule is already gone' do
      post '/mutes/delete', { kind: 'keyword', value: 'never-existed' }
      expect(last_response.location).to include('notice=mute-not-found')
    end

    it '400s on an unknown kind' do
      post '/mutes/delete', { kind: 'sideways', value: 'x' }
      expect(last_response.status).to eq(400)
    end
  end

  describe '/feeds renders the Muted section' do
    it 'shows existing rules with an Unmute button' do
      MuteRulesStore.add(user_id: 1, kind: 'keyword', value: 'crypto')
      get '/feeds'
      expect(last_response.body).to include('Muted')
      expect(last_response.body).to include('crypto')
      expect(last_response.body).to include('action="/mutes/delete"')
    end

    it 'shows the empty-state copy when no rules exist' do
      get '/feeds'
      expect(last_response.body).to include('No mute rules yet.')
    end
  end

  describe '/article/:uid surfaces the mute affordances' do
    it 'shows Mute author when the article has an author' do
      make_mute_article(uid: 'mutearticle1', author: 'Cory Doctorow')
      get '/article/mutearticle1'
      expect(last_response.body).to include('🚫 Mute author')
      expect(last_response.body).to include('value="Cory Doctorow"')
    end

    it 'omits Mute author when no author is present' do
      make_mute_article(uid: 'mutearticle2', author: nil)
      get '/article/mutearticle2'
      expect(last_response.body).not_to include('🚫 Mute author')
      # Mute keyword form is always present.
      expect(last_response.body).to include('🚫 Mute keyword')
    end
  end
end
