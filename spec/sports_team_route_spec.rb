require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/sports_teams'

# Sports Phase S6 (news-only v1) — per-team detail pages at
# /sports/team/:slug. Renders articles + podcast episodes from
# every catalog feed_url that belongs to that team AND is
# subscribed by the user. Empty state when no team feeds
# subscribed; 404 when the slug is unknown.

def add_team_feed_with_article(url:, title:, uid:)
  feed = FeedsStore.add(url: url, title: title, topic: 'sports')
  ArticlesStore.import(feed_id: feed['id'], entries: [{
    uid: uid, title: "Article from #{title}", url: "https://x.com/#{uid}",
    author: nil, published_at: '2026-05-08T12:00:00Z',
    content_html: '<p>x</p>', content_text: 'team article body',
    audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
  }])
  feed
end

RSpec.describe SportsTeams do
  it 'declares all six user teams (Eagles + Sixers + Union + NZ Rugby + Tennis)' do
    slugs = SportsTeams.all.map { |t| t[:slug] }
    expect(slugs).to contain_exactly('eagles', 'sixers', 'union', 'all-blacks', 'tennis')
  end

  it 'every team has the required keys' do
    SportsTeams.all.each do |team|
      expect(team.keys).to include(:slug, :name, :short_name, :sport, :emoji, :feed_urls, :blurb)
      expect(team[:feed_urls]).not_to be_empty
    end
  end

  it 'every team feed_url points at a real catalog entry' do
    SportsTeams.all.each do |team|
      team[:feed_urls].each do |url|
        expect(FeedCatalog.find_by_url(url)).not_to be_nil, "Team #{team[:slug]} references catalog-missing URL: #{url}"
      end
    end
  end

  describe '.find' do
    it 'returns the team for a known slug' do
      expect(SportsTeams.find('eagles')[:short_name]).to eq('Eagles')
    end

    it 'returns nil for an unknown slug' do
      expect(SportsTeams.find('made-up-slug')).to be_nil
    end
  end

  describe '.subscribed_feeds_for' do
    it 'returns only the catalog URLs the user has subscribed' do
      eagles = SportsTeams.find('eagles')
      expect(SportsTeams.subscribed_feeds_for(eagles)).to be_empty

      add_team_feed_with_article(
        url: 'https://www.bleedinggreennation.com/rss/index.xml',
        title: 'BGN', uid: 'teamsub01'
      )
      expect(SportsTeams.subscribed_feeds_for(eagles).map { |f| f['title'] }).to include('BGN')
    end

    it 'returns [] for nil team' do
      expect(SportsTeams.subscribed_feeds_for(nil)).to eq([])
    end
  end
end

RSpec.describe 'GET /sports/team/:slug' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'renders the team header + emoji when the team exists' do
    add_team_feed_with_article(
      url: 'https://www.bleedinggreennation.com/rss/index.xml',
      title: 'BGN', uid: 'team01'
    )
    get '/sports/team/eagles'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Philadelphia Eagles')
    expect(last_response.body).to include('🦅')
  end

  it 'renders articles from the team feeds' do
    add_team_feed_with_article(
      url: 'https://www.bleedinggreennation.com/rss/index.xml',
      title: 'BGN', uid: 'team02'
    )
    get '/sports/team/eagles'
    expect(last_response.body).to include('Article from BGN')
    expect(last_response.body).to include('href="/article/team02"')
    expect(last_response.body).to include('target="_blank"') # publisher link
  end

  it 'renders the empty state when no team feeds are subscribed' do
    get '/sports/team/eagles'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include("haven't subscribed to any Eagles feeds yet")
    # And lists the catalog candidates
    expect(last_response.body).to include('Bleeding Green Nation')
  end

  it '404s on an unknown slug' do
    get '/sports/team/middle-of-nowhere'
    expect(last_response.status).to eq(404)
  end

  it 'merges articles across multiple team feeds in chronological order' do
    add_team_feed_with_article(
      url: 'https://www.bleedinggreennation.com/rss/index.xml', title: 'BGN', uid: 'team03'
    )
    feed_b = FeedsStore.add(url: 'https://feeds.megaphone.fm/VMP9406149033', title: 'BGN Pod', topic: 'sports')
    ArticlesStore.import(feed_id: feed_b['id'], entries: [{
      uid: 'team04', title: 'Podcast episode',
      url: 'https://example.com/team04', author: nil,
      published_at: '2026-05-09T12:00:00Z',  # newer than team03
      content_html: '<p>x</p>', content_text: 'pod body',
      audio_url: 'https://example.com/team04.mp3', audio_mime_type: 'audio/mpeg', audio_duration_seconds: 1800
    }])

    get '/sports/team/eagles'
    body = last_response.body
    # Podcast episode (newer) should appear before BGN article in the rendered order.
    pod_pos = body.index('Podcast episode')
    bgn_pos = body.index('Article from BGN')
    expect(pod_pos).not_to be_nil
    expect(bgn_pos).not_to be_nil
    expect(pod_pos).to be < bgn_pos
  end
end

RSpec.describe '/sports TOC team buttons' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'omits team buttons when no team feeds are subscribed' do
    get '/sports'
    expect(last_response.body).not_to include('class="sports-toc-row sports-toc-teams"')
  end

  it 'renders a team button for each team that has at least one subscription' do
    add_team_feed_with_article(
      url: 'https://www.bleedinggreennation.com/rss/index.xml',
      title: 'BGN', uid: 'tocteam01'
    )
    get '/sports'
    expect(last_response.body).to include('class="sports-toc-row sports-toc-teams"')
    expect(last_response.body).to include('href="/sports/team/eagles"')
    expect(last_response.body).to include('Eagles')
    # Sixers has no subscription — should NOT render
    expect(last_response.body).not_to include('href="/sports/team/sixers"')
  end
end
