require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'

# Sports Phase S5 (news-only v1) — /sports overview page.
# Aggregates the user's subscribed sports feeds + recent articles
# per sport. Live scores / fixtures / standings come later when
# Phase S3+ adds structured-data tables.

def add_sports_subscription(url:, title:, category: :nfl, with_article_uid: nil)
  feed = FeedsStore.add(url: url, title: title, topic: 'sports')
  if with_article_uid
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: with_article_uid, title: "Article from #{title}",
      url: "https://x.com/#{with_article_uid}", author: nil,
      published_at: '2026-05-08T12:00:00Z',
      content_html: '<p>x</p>', content_text: 'x',
      audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
    }])
  end
  feed
end

RSpec.describe 'GET /sports' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  it 'renders the empty state when no sports feeds are subscribed' do
    # No sports feeds in DB.
    get '/sports'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('No sports feeds subscribed yet')
    expect(last_response.body).to include('Subscribe to a sports feed')
  end

  it 'lists subscribed sports feeds in the right per-sport sections' do
    add_sports_subscription(
      url:   'https://www.bleedinggreennation.com/rss/index.xml', # in catalog as :nfl
      title: 'Bleeding Green Nation',
      with_article_uid: 'sportsovr01'
    )
    add_sports_subscription(
      url:   'https://feeds.acast.com/public/shows/thetennispodcast', # in catalog as :tennis
      title: 'The Tennis Podcast',
      with_article_uid: 'sportsovr02'
    )

    get '/sports'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('NFL')
    expect(last_response.body).to include('Tennis')
    expect(last_response.body).to include('Bleeding Green Nation')
    expect(last_response.body).to include('The Tennis Podcast')
    expect(last_response.body).to include('Article from Bleeding Green Nation')
    expect(last_response.body).to include('Article from The Tennis Podcast')
  end

  it 'links the headline to the publisher in a new tab + offers an in-app link' do
    add_sports_subscription(
      url: 'https://www.bleedinggreennation.com/rss/index.xml',
      title: 'BGN', with_article_uid: 'sportsovr03'
    )
    get '/sports'
    body = last_response.body
    expect(body).to match(%r{<a href="https://x\.com/sportsovr03"\s+target="_blank"\s+rel="noopener noreferrer"})
    expect(body).to include('href="/article/sportsovr03"')
    expect(body).to include('Open in app')
  end

  it 'renders a TOC pill button anchored to each non-empty sport section' do
    add_sports_subscription(
      url: 'https://www.bleedinggreennation.com/rss/index.xml',
      title: 'BGN', with_article_uid: 'sportsovr03toc'
    )
    get '/sports'
    expect(last_response.body).to include('class="sports-toc"')
    expect(last_response.body).to include('href="#sports-nfl"')
    expect(last_response.body).to include('id="sports-nfl"')
  end

  it 'omits sport sections that have no subscribed feeds AND no recent articles' do
    add_sports_subscription(
      url: 'https://www.bleedinggreennation.com/rss/index.xml',
      title: 'BGN', with_article_uid: 'sportsovr04'
    )
    get '/sports'
    # Has NFL (subscribed)
    expect(last_response.body).to include('class="benchmark-section sports-section sports-nfl"')
    # No NBA / Rugby / Tennis sections rendered
    expect(last_response.body).not_to include('sports-section sports-nba')
    expect(last_response.body).not_to include('sports-section sports-rugby')
  end

  it 'surfaces an Other sports feeds section for sports-tagged URLs not in the catalog' do
    FeedsStore.add(url: 'https://example.com/uncatalogued-sport', title: 'Random Sport Blog', topic: 'sports')
    get '/sports'
    expect(last_response.body).to include('Other sports feeds')
    expect(last_response.body).to include('Random Sport Blog')
  end

  it 'header summary counts feeds + sports correctly' do
    add_sports_subscription(url: 'https://www.bleedinggreennation.com/rss/index.xml', title: 'BGN')
    add_sports_subscription(url: 'https://www.libertyballers.com/rss/index.xml', title: 'LB')
    get '/sports'
    expect(last_response.body).to match(/2 feeds across\s+2 sports/)
  end

  it 'renders article summary inline (extractive cache or content_text excerpt)' do
    feed = FeedsStore.add(url: 'https://www.bleedinggreennation.com/rss/index.xml', title: 'BGN', topic: 'sports')
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: 'sportsovr05', title: 'Eagles win the division',
      url: 'https://example.com/eagles', author: 'Beat Writer',
      published_at: '2026-05-08T12:00:00Z',
      content_html: '<p>Body</p>',
      content_text: 'The Eagles clinched the NFC East with a decisive win over Dallas, sealing a playoff berth.',
      audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
    }])
    get '/sports'
    expect(last_response.body).to include('class="sports-article-summary"')
    expect(last_response.body).to include('Eagles clinched')
  end

  it 'top nav highlights the Sports tab when on /sports' do
    # STUFF #65 — Sports moved into the Browse ▾ dropdown; the link
    # now carries `role="menuitem"` so the assertion has to allow
    # arbitrary attributes between `href` and `class="active"`.
    get '/sports'
    expect(last_response.body).to match(%r{<a href="/sports"[^>]*class="active"[^>]*>Sports</a>})
  end
end
