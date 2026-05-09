require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/sports_players_store'
require_relative '../app/sports_teams_store'
require_relative '../app/sports_leagues_store'
require_relative '../app/sports_entity_articles_store'

# Phase S7 follow-up #2 — articles-mentioning-entity cache.
#
# Confirms: FTS5 phrase MATCH on the entity name populates the
# join table; refresh-if-stale skips work within TTL; the player +
# team detail pages surface the cached list.

def make_mention_player(slug:, full_name:)
  SportsPlayersStore.upsert(
    sport: 'tennis', slug: slug, full_name: full_name,
    tour: 'atp', current_rank: 1,
    source_provider: 'espn', external_id: slug.tr('-', '')
  )
end

def make_mention_article(uid:, title:, content: 'body content', feed_url: nil)
  feed_url ||= 'https://example.com/feed'
  feed = FeedsStore.find_by_url(feed_url) || FeedsStore.add(url: feed_url, title: 'Test Feed')
  ArticlesStore.import(feed_id: feed['id'], entries: [{
    uid: uid, title: title, url: "https://x.com/#{uid}",
    author: nil, published_at: '2026-05-08T12:00:00Z',
    content_html: "<p>#{content}</p>", content_text: content,
    audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
  }])
  ArticlesStore.find_by_uid(uid)
end

RSpec.describe SportsEntityArticlesStore, '.refresh_for + .for_entity' do
  it 'caches FTS5 phrase hits for a player by full_name' do
    make_mention_player(slug: 'jannik-sinner', full_name: 'Jannik Sinner')
    make_mention_article(uid: 'a01', title: 'Jannik Sinner wins Rome', content: 'Jannik Sinner triumphed today.')
    make_mention_article(uid: 'a02', title: 'Tennis update', content: 'Alcaraz won in Madrid.')

    player = SportsPlayersStore.find_by_slug('jannik-sinner')
    result = SportsEntityArticlesStore.refresh_for(
      kind: 'player', entity_id: player['id'], name: player['full_name']
    )
    expect(result[:total]).to eq(1)
    expect(result[:inserted]).to eq(1)

    cached = SportsEntityArticlesStore.for_entity(kind: 'player', entity_id: player['id'])
    expect(cached.map { |a| a['uid'] }).to eq(['a01'])
  end

  it 'is idempotent — second refresh with no new articles inserts 0' do
    make_mention_player(slug: 'sinner-id', full_name: 'Sinner ID')
    make_mention_article(uid: 'b01', title: 'Sinner ID wins again', content: 'Sinner ID lifted the trophy.')
    player = SportsPlayersStore.find_by_slug('sinner-id')

    SportsEntityArticlesStore.refresh_for(
      kind: 'player', entity_id: player['id'], name: player['full_name'], force: true
    )
    second = SportsEntityArticlesStore.refresh_for(
      kind: 'player', entity_id: player['id'], name: player['full_name'], force: true
    )
    expect(second[:inserted]).to eq(0)
    expect(second[:total]).to eq(1)
  end

  it 'skips work when articles_indexed_at is within TTL' do
    make_mention_player(slug: 'fresh-cache', full_name: 'Fresh Cache')
    player = SportsPlayersStore.find_by_slug('fresh-cache')
    SportsEntityArticlesStore.stamp_indexed!(kind: 'player', entity_id: player['id'])
    result = SportsEntityArticlesStore.refresh_for(
      kind: 'player', entity_id: player['id'], name: player['full_name']
    )
    expect(result).to eq(skipped: true, reason: :fresh)
  end

  it 'phrase-matches — does not match when only one word appears' do
    make_mention_player(slug: 'jannik-only', full_name: 'Jannik Only')
    # An article with "Jannik" but not "Only" together as a phrase.
    make_mention_article(uid: 'p01', title: 'Random Jannik scattered Only',
                 content: 'Jannik did one thing. Separately, Only matters.')
    player = SportsPlayersStore.find_by_slug('jannik-only')
    SportsEntityArticlesStore.refresh_for(
      kind: 'player', entity_id: player['id'], name: player['full_name'], force: true
    )
    cached = SportsEntityArticlesStore.for_entity(kind: 'player', entity_id: player['id'])
    expect(cached).to be_empty
  end

  it 'rejects unknown kinds' do
    expect {
      SportsEntityArticlesStore.refresh_for(kind: 'banana', entity_id: 1, name: 'x')
    }.to raise_error(ArgumentError)
  end
end

RSpec.describe SportsEntityArticlesStore, '.refresh_for for teams' do
  it 'caches phrase hits for team name' do
    league = SportsLeaguesStore.upsert(
      slug: 'nfl', name: 'NFL', sport: 'football',
      source_provider: 'espn', external_id: 'nfl'
    )
    team = SportsTeamsStore.upsert(
      slug: 'philadelphia-eagles', name: 'Philadelphia Eagles', short_name: 'Eagles',
      league_id: league['id'], source_provider: 'espn', external_id: 'phi-21'
    )
    make_mention_article(uid: 't01', title: 'Philadelphia Eagles draft news',
                 content: 'The Philadelphia Eagles selected three players today.')
    make_mention_article(uid: 't02', title: 'Other NFL teams', content: 'Cowboys did things.')

    SportsEntityArticlesStore.refresh_for(
      kind: 'team', entity_id: team['id'], name: 'Philadelphia Eagles'
    )
    cached = SportsEntityArticlesStore.for_entity(kind: 'team', entity_id: team['id'])
    expect(cached.map { |a| a['uid'] }).to eq(['t01'])
  end
end

RSpec.describe '/sports/player/:slug articles section' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'renders the Articles mentioning section with cached hits after first visit' do
    make_mention_player(slug: 'coco-gauff', full_name: 'Coco Gauff')
    make_mention_article(uid: 'cg01', title: 'Coco Gauff wins Madrid',
                 content: 'Coco Gauff completed the comeback in Madrid today.')

    get '/sports/player/coco-gauff'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Articles mentioning Coco Gauff')
    expect(last_response.body).to include('Coco Gauff wins Madrid')
  end

  it 'renders the empty-state message when no hits' do
    make_mention_player(slug: 'unknown-player', full_name: 'Unknown Player')
    get '/sports/player/unknown-player'
    expect(last_response.body).to include('Articles mentioning Unknown Player')
    expect(last_response.body).to include('No articles mentioning')
  end
end
