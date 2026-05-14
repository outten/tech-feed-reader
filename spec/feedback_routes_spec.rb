require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/read_state_store'
require_relative '../app/feed_feedback_store'

RSpec.describe 'POST /article/:uid/feedback' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  def make_article(uid: 'fbroute0001')
    feed = FeedsStore.find_by_url('https://x.com/fbroute') ||
           FeedsStore.add(url: 'https://x.com/fbroute', title: 'FB Route Feed')
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: uid, title: 'A', url: "https://x.com/#{uid}", author: nil,
      published_at: '2026-05-05T12:00:00Z',
      content_html: '<p>x</p>', content_text: 'x',
      audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
    }])
    ArticlesStore.find_by_uid(uid)
  end

  it 'persists +1 when value=1 is submitted' do
    article = make_article
    post "/article/#{article['uid']}/feedback", { value: '1' }
    expect(last_response.status).to eq(302)
    expect(ReadStateStore.get(1, article['id'])['feedback']).to eq(1)
  end

  it 'persists -1 when value=-1 is submitted' do
    article = make_article
    post "/article/#{article['uid']}/feedback", { value: '-1' }
    expect(ReadStateStore.get(1, article['id'])['feedback']).to eq(-1)
  end

  it 'clears via value=0 (toggle)' do
    article = make_article
    ReadStateStore.mark_feedback(1, article['id'], value: 1)
    post "/article/#{article['uid']}/feedback", { value: '0' }
    expect(ReadStateStore.get(1, article['id'])['feedback']).to eq(0)
  end

  it '400s on an invalid value' do
    article = make_article
    post "/article/#{article['uid']}/feedback", { value: '99' }
    expect(last_response.status).to eq(400)
  end

  it '404s on an unknown uid' do
    post '/article/nosuchart01/feedback', { value: '1' }
    expect(last_response.status).to eq(404)
  end

  it 'redirects to /article/:uid by default; honours return_to' do
    article = make_article
    post "/article/#{article['uid']}/feedback", { value: '1' }
    expect(last_response.headers['Location']).to end_with("/article/#{article['uid']}")

    post "/article/#{article['uid']}/feedback", { value: '0', return_to: '/articles?state=unread' }
    expect(last_response.headers['Location']).to end_with('/articles?state=unread')
  end
end

RSpec.describe 'POST /feeds/:id/feedback' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  it 'bumps weight up by STEP (0.25) on direction=up' do
    feed = FeedsStore.add(url: 'https://x.com/feedrt', title: 'X')
    post "/feeds/#{feed['id']}/feedback", { direction: 'up' }
    expect(last_response.status).to eq(302)
    expect(FeedFeedbackStore.weight_for(1, feed['id'])).to eq(1.25)
  end

  it 'bumps weight down by STEP on direction=down' do
    feed = FeedsStore.add(url: 'https://x.com/feedrt', title: 'X')
    post "/feeds/#{feed['id']}/feedback", { direction: 'down' }
    expect(FeedFeedbackStore.weight_for(1, feed['id'])).to eq(0.75)
  end

  it 'resets via direction=reset (deletes the row, returns to default)' do
    feed = FeedsStore.add(url: 'https://x.com/feedrt', title: 'X')
    FeedFeedbackStore.bump(1, feed['id'], direction: :up)
    FeedFeedbackStore.bump(1, feed['id'], direction: :up)
    expect(FeedFeedbackStore.count(1)).to eq(1)

    post "/feeds/#{feed['id']}/feedback", { direction: 'reset' }
    expect(FeedFeedbackStore.weight_for(1, feed['id'])).to eq(1.0)
    expect(FeedFeedbackStore.count(1)).to eq(0)
  end

  it '400s on an invalid direction' do
    feed = FeedsStore.add(url: 'https://x.com/feedrt', title: 'X')
    post "/feeds/#{feed['id']}/feedback", { direction: 'sideways' }
    expect(last_response.status).to eq(400)
  end

  it '404s on an unknown feed id' do
    post '/feeds/99999/feedback', { direction: 'up' }
    expect(last_response.status).to eq(404)
  end

  it 'redirects to /feeds by default; honours return_to' do
    feed = FeedsStore.add(url: 'https://x.com/feedrt', title: 'X')
    post "/feeds/#{feed['id']}/feedback", { direction: 'up' }
    expect(last_response.headers['Location']).to end_with('/feeds')

    post "/feeds/#{feed['id']}/feedback", { direction: 'up', return_to: '/dashboard' }
    expect(last_response.headers['Location']).to end_with('/dashboard')
  end
end

RSpec.describe 'Feedback UI surfaces' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  def make_article(uid: 'fbview00001')
    feed = FeedsStore.find_by_url('https://x.com/fbview') ||
           FeedsStore.add(url: 'https://x.com/fbview', title: 'FB View Feed')
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: uid, title: 'View Test', url: "https://x.com/#{uid}", author: nil,
      published_at: '2026-05-05T12:00:00Z',
      content_html: '<p>x</p>', content_text: 'x',
      audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
    }])
    ArticlesStore.find_by_uid(uid)
  end

  describe '/article/:uid action row' do
    it 'renders idle 👍 / 👎 buttons posting to /feedback when no signal exists' do
      article = make_article
      get "/article/#{article['uid']}"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include(%(action="/article/#{article['uid']}/feedback"))
      # Idle state: button text is the bare emoji (whitespace tolerated
      # because ERB indentation sneaks newlines into <button>...</button>).
      expect(last_response.body).to match(/<button[^>]*>\s*👍\s*<\/button>/)
      expect(last_response.body).to match(/<button[^>]*>\s*👎\s*<\/button>/)
      expect(last_response.body).not_to include('feedback-on-up')
      expect(last_response.body).not_to include('feedback-on-down')
    end

    it 'highlights the 👍 button when feedback is +1' do
      article = make_article
      ReadStateStore.mark_feedback(1, article['id'], value: 1)
      get "/article/#{article['uid']}"
      expect(last_response.body).to include('feedback-on-up')
      expect(last_response.body).to include('👍 Boosted')
      # The active form posts value=0 to clear
      expect(last_response.body).to match(%r{<form method="post" action="/article/#{article['uid']}/feedback">\s*<input type="hidden" name="value" value="0">})
    end

    it 'highlights the 👎 button when feedback is -1' do
      article = make_article
      ReadStateStore.mark_feedback(1, article['id'], value: -1)
      get "/article/#{article['uid']}"
      expect(last_response.body).to include('feedback-on-down')
      expect(last_response.body).to include('👎 Demoted')
    end
  end

  describe '/articles row inline affordances' do
    it 'renders per-row 👍/👎 forms with the correct toggle targets' do
      article = make_article
      get '/articles'
      expect(last_response.status).to eq(200)
      # One thumbs-up form posting value=1 (idle → boost) and one
      # thumbs-down form posting value=-1.
      expect(last_response.body).to match(%r{<form method="post" action="/article/#{article['uid']}/feedback">\s*<input type="hidden" name="value" value="1">})
      expect(last_response.body).to match(%r{<form method="post" action="/article/#{article['uid']}/feedback">\s*<input type="hidden" name="value" value="-1">})
      # return_to round-trips back to /articles
      expect(last_response.body).to include(%(name="return_to" value="/articles"))
    end

    it 'flips the toggle target + adds .feedback-set when the article has been voted on' do
      article = make_article
      ReadStateStore.mark_feedback(1, article['id'], value: 1)
      get '/articles'
      # The 👍 button is now in is-on state and posts value=0 to clear
      expect(last_response.body).to include('feedback-set')
      expect(last_response.body).to match(%r{<button type="submit" class="feedback-row-btn is-on"\s+title="Clear the thumbs-up on this article"})
    end
  end

  describe '/feeds row weight controls' do
    it 'renders the +/- buttons + the current weight readout for every feed' do
      feed = FeedsStore.add(url: 'https://x.com/fbview2', title: 'Weight Feed')
      get '/feeds'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include(%(action="/feeds/#{feed['id']}/feedback"))
      expect(last_response.body).to include('name="direction" value="up"')
      expect(last_response.body).to include('name="direction" value="down"')
      expect(last_response.body).to include('1.00×')           # default weight
      expect(last_response.body).to include('feed-row-weight is-default')
    end

    it 'reflects a non-default stored weight in the readout + drops the .is-default modifier' do
      feed = FeedsStore.add(url: 'https://x.com/fbview3', title: 'Weighted Feed')
      FeedFeedbackStore.bump(1, feed['id'], direction: :up)  # 1.25
      FeedFeedbackStore.bump(1, feed['id'], direction: :up)  # 1.50
      get '/feeds'
      expect(last_response.body).to include('1.50×')
      # The is-default modifier shouldn't be on this feed's row.
      row_html = last_response.body[/<tr data-feed-id="#{feed['id']}".*?<\/tr>/m]
      expect(row_html).not_to include('feed-row-weight is-default')
      expect(row_html).to     include('feed-row-weight ')  # plain (no is-default)
    end
  end
end
