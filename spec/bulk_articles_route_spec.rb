require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/read_state_store'

RSpec.describe 'POST /api/articles/bulk' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  def add_articles(count)
    feed = FeedsStore.add(url: 'https://example.com/rss', title: 'Example')
    count.times.map do |i|
      ArticlesStore.import(feed_id: feed['id'], entries: [{
        uid:           "bulkitem#{i.to_s.rjust(4, '0')}",
        title:         "Item #{i}",
        url:           "https://example.com/#{i}",
        author:        nil,
        published_at:  Time.utc(2026, 5, 4, 10, i).iso8601,
        content_html:  '<p>Body</p>',
        content_text:  'Body',
        audio_url:     nil,
        audio_mime_type:        nil,
        audio_duration_seconds: nil
      }])
      ArticlesStore.find_by_uid("bulkitem#{i.to_s.rjust(4, '0')}")
    end
  end

  def post_bulk(payload)
    post '/api/articles/bulk', payload.to_json, 'CONTENT_TYPE' => 'application/json'
  end

  it 'marks every uid in the list as read in a single call' do
    rows = add_articles(3)
    uids = rows.map { |r| r['uid'] }

    post_bulk(uids: uids, action: 'read')
    expect(last_response.status).to eq(200)
    body = JSON.parse(last_response.body)
    expect(body['status']).to  eq('ok')
    expect(body['action']).to  eq('read')
    expect(body['applied']).to eq(3)
    expect(body['total']).to   eq(3)
    expect(body['results'].map { |r| r['ok'] }).to all(be true)

    rows.each do |r|
      state = ReadStateStore.get(r['id'])
      expect(state['read']).to eq(1)
    end
  end

  it 'supports the full action whitelist (read/unread/bookmark/unbookmark/archive/unarchive)' do
    row = add_articles(1).first

    %w[read unread bookmark unbookmark archive unarchive].each do |action|
      post_bulk(uids: [row['uid']], action: action)
      expect(last_response.status).to eq(200), "action=#{action} failed: #{last_response.body}"
      expect(JSON.parse(last_response.body)['action']).to eq(action)
    end

    state = ReadStateStore.get(row['id'])
    expect(state['read']).to       eq(0)  # last action was unarchive; before that, unbookmark; read was set then unset
    expect(state['bookmarked']).to eq(0)
    expect(state['archived']).to   eq(0)
  end

  it 'returns 400 with the allowed list when action is unknown' do
    post_bulk(uids: ['anything'], action: 'delete')
    expect(last_response.status).to eq(400)
    body = JSON.parse(last_response.body)
    expect(body['error']).to include('unknown action')
    expect(body['allowed']).to include('read', 'archive', 'bookmark')
  end

  it 'returns 400 when uids is missing or empty' do
    post_bulk(action: 'read')
    expect(last_response.status).to eq(400)
    expect(JSON.parse(last_response.body)['error']).to include('uids must be a non-empty array')

    post_bulk(uids: [], action: 'read')
    expect(last_response.status).to eq(400)
  end

  it 'returns 400 on invalid JSON' do
    post '/api/articles/bulk', 'not-json', 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eq(400)
  end

  it 'reports per-uid result rows for unknown uids without aborting the batch' do
    rows = add_articles(2)
    uids = [rows[0]['uid'], 'doesnotexis1', rows[1]['uid']]

    post_bulk(uids: uids, action: 'archive')
    expect(last_response.status).to eq(200)
    body = JSON.parse(last_response.body)
    expect(body['applied']).to eq(2)
    expect(body['total']).to   eq(3)
    by_uid = body['results'].each_with_object({}) { |r, h| h[r['uid']] = r }
    expect(by_uid[rows[0]['uid']]['ok']).to be(true)
    expect(by_uid[rows[1]['uid']]['ok']).to be(true)
    expect(by_uid['doesnotexis1']['ok']).to    be(false)
    expect(by_uid['doesnotexis1']['error']).to eq('not_found')

    # The two real rows ARE archived even though one uid in the batch failed.
    rows.each do |r|
      expect(ReadStateStore.get(r['id'])['archived']).to eq(1)
    end
  end

  it 'caps the batch at BULK_UIDS_MAX uids per request' do
    cap  = TechFeedReader::BULK_UIDS_MAX
    uids = (cap + 5).times.map { |i| "padded%07d" % i }
    post_bulk(uids: uids, action: 'read')
    expect(last_response.status).to eq(200)
    body = JSON.parse(last_response.body)
    expect(body['total']).to eq(cap)
  end

  it 'de-duplicates uids in the input list before processing' do
    row = add_articles(1).first
    post_bulk(uids: [row['uid'], row['uid'], row['uid']], action: 'read')
    expect(last_response.status).to eq(200)
    body = JSON.parse(last_response.body)
    expect(body['total']).to eq(1)
    expect(body['applied']).to eq(1)
  end
end

RSpec.describe '/articles bulk-toolbar surface' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  it 'renders the toolbar markup + checkboxes + the bulk-actions JS on /articles' do
    feed = FeedsStore.add(url: 'https://example.com/rss', title: 'Example')
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid: 'rowwithcheck', title: 'A',
      url: 'https://example.com/a', author: nil,
      published_at: '2026-05-04T12:00:00Z',
      content_html: '<p>x</p>', content_text: 'x',
      audio_url: nil, audio_mime_type: nil, audio_duration_seconds: nil
    }])

    get '/articles'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('id="bulk-toolbar"')
    expect(last_response.body).to include('data-bulk-action="read"')
    expect(last_response.body).to include('data-bulk-action="archive"')
    expect(last_response.body).to include('class="news-item-check"')
    expect(last_response.body).to include('data-uid="rowwithcheck"')
    expect(last_response.body).to include('bulk-actions.js')
  end
end
