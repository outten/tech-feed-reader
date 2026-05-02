require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'
require_relative '../app/opml'

RSpec.describe 'OPML routes' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  let(:opml_body) do
    <<~XML
      <?xml version="1.0"?>
      <opml version="2.0">
        <head><title>my feeds</title></head>
        <body>
          <outline type="rss" title="HN"       xmlUrl="https://news.ycombinator.com/rss"/>
          <outline type="rss" title="Lobsters" xmlUrl="https://lobste.rs/rss"/>
        </body>
      </opml>
    XML
  end

  describe 'POST /feeds/import' do
    it 'adds new feeds and reports counts via flash' do
      file = Rack::Test::UploadedFile.new(StringIO.new(opml_body), 'text/x-opml', original_filename: 'feeds.opml')
      post '/feeds/import', { 'file' => file }
      expect(last_response.status).to eq(302)
      loc = last_response.headers['Location']
      expect(loc).to include('notice=imported')
      expect(loc).to include('added=2')
      expect(loc).to include('skipped=0')
      expect(loc).to include('total=2')
      expect(FeedsStore.find_by_url('https://news.ycombinator.com/rss')).not_to be_nil
      expect(FeedsStore.find_by_url('https://lobste.rs/rss')).not_to be_nil
    end

    it 'is idempotent — re-importing skips already-subscribed URLs' do
      FeedsStore.add(url: 'https://news.ycombinator.com/rss', title: 'HN')

      file = Rack::Test::UploadedFile.new(StringIO.new(opml_body), 'text/x-opml', original_filename: 'feeds.opml')
      post '/feeds/import', { 'file' => file }
      loc = last_response.headers['Location']
      expect(loc).to include('added=1')
      expect(loc).to include('skipped=1')
      expect(FeedsStore.count).to eq(2)
    end

    it 'redirects with error=missing-file when no file is supplied' do
      post '/feeds/import'
      expect(last_response.headers['Location']).to include('error=missing-file')
    end

    it 'reports added=0 for an OPML file with no <outline xmlUrl="…"> entries' do
      empty = '<opml version="2.0"><head/><body><outline title="folder"/></body></opml>'
      file  = Rack::Test::UploadedFile.new(StringIO.new(empty), 'text/x-opml', original_filename: 'empty.opml')
      post '/feeds/import', { 'file' => file }
      expect(last_response.headers['Location']).to include('added=0')
      expect(last_response.headers['Location']).to include('total=0')
    end
  end

  describe 'GET /feeds/export.opml' do
    it 'returns text/x-opml with one outline per feed' do
      FeedsStore.add(url: 'https://a.example.com/rss', title: 'A')
      FeedsStore.add(url: 'https://b.example.com/rss', title: 'B')

      get '/feeds/export.opml'
      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('text/x-opml')
      expect(last_response.headers['Content-Disposition']).to include('attachment')
      expect(last_response.headers['Content-Disposition']).to include('.opml')

      doc      = Nokogiri::XML(last_response.body)
      outlines = doc.css('body > outline')
      expect(outlines.length).to eq(2)
      expect(outlines.map { |o| o['xmlUrl'] }).to contain_exactly(
        'https://a.example.com/rss', 'https://b.example.com/rss'
      )
    end

    it 'returns a valid (empty body) document when no feeds exist' do
      get '/feeds/export.opml'
      expect(last_response.status).to eq(200)
      doc = Nokogiri::XML(last_response.body)
      expect(doc.at_css('opml')).not_to be_nil
      expect(doc.css('body > outline')).to be_empty
    end
  end

  describe 'round-trip via the routes' do
    it 'export → import on a fresh DB recreates the same feed list' do
      FeedsStore.add(url: 'https://a.example.com/rss', title: 'A')
      FeedsStore.add(url: 'https://b.example.com/rss', title: 'B')

      get '/feeds/export.opml'
      exported = last_response.body

      Database.connection.execute('DELETE FROM feeds')
      expect(FeedsStore.count).to eq(0)

      file = Rack::Test::UploadedFile.new(StringIO.new(exported), 'text/x-opml', original_filename: 'export.opml')
      post '/feeds/import', { 'file' => file }
      titles = FeedsStore.all.map { |f| f['title'] }
      expect(titles).to contain_exactly('A', 'B')
    end
  end
end
