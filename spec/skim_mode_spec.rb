require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/read_state_store'
require_relative '../app/summary_store'

RSpec.describe 'GET /articles?view=skim' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  def add_article(uid:, title:, content_text: 'Default body text.', published_at: '2026-05-04T12:00:00Z')
    feed = FeedsStore.find_by_url('https://example.com/rss') ||
           FeedsStore.add(url: 'https://example.com/rss', title: 'Example')
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: uid, title: title,
      url: "https://example.com/#{uid}", author: nil,
      published_at: published_at,
      content_html: "<p>#{content_text}</p>", content_text: content_text,
      audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
    }])
    ArticlesStore.find_by_uid(uid)
  end

  describe 'page header chip' do
    it 'renders the Skim toggle in inactive state by default' do
      add_article(uid: 'aaaaaaaaaaaa', title: 'A')
      get '/articles'
      expect(last_response.status).to eq(200)
      # Default page (no kind filter): the off-state link adds view=skim.
      expect(last_response.body).to include('<a href="?state=all&view=skim">skim</a>')
    end

    it 'renders the Skim chip in active state when ?view=skim is set' do
      add_article(uid: 'aaaaaaaaaaaa', title: 'A')
      get '/articles?view=skim'
      expect(last_response.status).to eq(200)
      # Active link drops view=skim from the href so clicking toggles off.
      expect(last_response.body).to include('<a href="?state=all" class="active">skim</a>')
    end

    it 'preserves state + kind filters when toggling Skim on/off' do
      add_article(uid: 'aaaaaaaaaaaa', title: 'A')
      get '/articles?state=unread&kind=podcast&view=skim'
      # The "skim → off" link keeps state=unread + kind=podcast.
      expect(last_response.body).to include('<a href="?state=unread&kind=podcast" class="active">skim</a>')
      # The state-filter chips keep view=skim in their query.
      expect(last_response.body).to include('href="?state=all&kind=podcast&view=skim"')
    end
  end

  describe '.news-list class + per-row summary' do
    it 'adds the `skim` modifier class to .news-list only when view=skim' do
      add_article(uid: 'aaaaaaaaaaaa', title: 'A')

      get '/articles'
      expect(last_response.body).to match(%r{<ul class="news-list ">})

      get '/articles?view=skim'
      expect(last_response.body).to match(%r{<ul class="news-list skim">})
    end

    it 'omits the .news-summary-skim line outside skim mode' do
      art = add_article(uid: 'aaaaaaaaaaaa', title: 'Title')
      SummaryStore.upsert(art['id'], extractive: 'should not appear')
      get '/articles'
      expect(last_response.body).not_to include('news-summary-skim')
      expect(last_response.body).not_to include('should not appear')
    end

    it 'prefers the LLM summary when present' do
      art = add_article(uid: 'aaaaaaaaaaaa', title: 'Title', content_text: 'raw body should not show in summary')
      SummaryStore.upsert(art['id'], llm: 'llm summary preferred', llm_model: 'claude-x', extractive: 'extractive should be hidden')

      get '/articles?view=skim'
      expect(last_response.body).to include('news-summary-skim')
      expect(last_response.body).to include('llm summary preferred')
      expect(last_response.body).not_to include('extractive should be hidden')
      expect(last_response.body).not_to include('raw body should not show')
    end

    it 'falls back to the extractive summary when no LLM summary exists' do
      art = add_article(uid: 'bbbbbbbbbbbb', title: 'Title', content_text: 'raw body')
      SummaryStore.upsert(art['id'], extractive: 'extractive fallback used')

      get '/articles?view=skim'
      expect(last_response.body).to include('extractive fallback used')
    end

    it 'falls back to a content_text excerpt when no summary row exists at all' do
      art = add_article(uid: 'cccccccccccc', title: 'Title', content_text: 'raw content excerpt for fallback display')
      # ArticlesStore.import auto-generates an extractive summary; remove it
      # to test the no-summary-row fallback specifically.
      SummaryStore.remove(art['id'])
      get '/articles?view=skim'
      expect(last_response.body).to include('raw content excerpt for fallback display')
    end

    it 'truncates the content_text fallback to ~240 chars with an ellipsis' do
      long = 'word ' * 100  # 500 chars; "word " is 5 chars so well over 240
      art = add_article(uid: 'dddddddddddd', title: 'Title', content_text: long)
      # Defeat the auto-generated extractive summary so we test the
      # content_text excerpt path specifically.
      SummaryStore.remove(art['id'])
      get '/articles?view=skim'
      expect(last_response.body).to match(/<p class="news-summary-skim">[^<]*…<\/p>/)
    end

    it 'omits the summary line entirely when no LLM, no extractive, and no content_text' do
      art = add_article(uid: 'eeeeeeeeeeee', title: 'Title', content_text: '   ')
      SummaryStore.remove(art['id'])  # any auto-generated extractive
      get '/articles?view=skim'
      expect(last_response.body).not_to include('news-summary-skim')
    end
  end

  describe 'invalid ?view= values' do
    it 'falls back to the default view when ?view is anything other than `skim`' do
      add_article(uid: 'aaaaaaaaaaaa', title: 'A')
      get '/articles?view=spaceship'
      expect(last_response.body).not_to match(%r{<ul class="news-list skim">})
      expect(last_response.body).to     match(%r{<ul class="news-list ">})
    end
  end
end

RSpec.describe SummaryStore, '.find_for_ids' do
  it 'returns an empty hash for an empty input list' do
    expect(SummaryStore.find_for_ids([])).to eq({})
    expect(SummaryStore.find_for_ids(nil)).to eq({})
  end

  it 'returns one row per matching article_id, keyed by id' do
    feed = FeedsStore.add(url: 'https://example.com/rss', title: 'Example')
    ArticlesStore.import(feed_id: feed['id'], entries: [
      { uid: 'art1art1art1', title: 'A', url: 'https://example.com/1', author: nil,
        published_at: '2026-05-04T12:00:00Z', content_html: '<p>x</p>', content_text: 'x',
        audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil },
      { uid: 'art2art2art2', title: 'B', url: 'https://example.com/2', author: nil,
        published_at: '2026-05-04T12:00:00Z', content_html: '<p>x</p>', content_text: 'x',
        audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil }
    ])
    a = ArticlesStore.find_by_uid('art1art1art1')
    b = ArticlesStore.find_by_uid('art2art2art2')
    # ArticlesStore.import auto-generates extractive summaries on every
    # import; clear b's so we can verify the lookup omits article_ids
    # without a row.
    SummaryStore.remove(b['id'])
    SummaryStore.upsert(a['id'], extractive: 'a-summary')

    rows = SummaryStore.find_for_ids([a['id'], b['id']])
    expect(rows.keys).to contain_exactly(a['id'])
    expect(rows[a['id']]['extractive']).to eq('a-summary')
  end
end
