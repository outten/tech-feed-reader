require_relative 'spec_helper'
require_relative '../app/feeds_store'
require_relative '../app/articles_store'
require_relative '../app/providers/readability'

# Integration: stub the Readability HTTP layer with a substantive
# article page, import a teaser-style entry, and verify the article
# row ends up with the extracted body — not the original placeholder.
RSpec.describe 'Readability fallback during ArticlesStore.import' do
  let(:article_html) { File.read(File.expand_path('fixtures/article_page.html', __dir__)) }
  let(:feed)         { FeedsStore.add(url: 'https://lobste.rs/rss') }

  def stub_origin(body:, code: 200)
    response = instance_double(Net::HTTPResponse, code: code.to_s, body: body)
    allow(response).to receive(:[]) { |_| nil }
    allow(Providers::HttpClient).to receive(:get).and_return(response)
  end

  it 'replaces a teaser body with the readability-extracted text' do
    stub_origin(body: article_html)

    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid:          'a' * 12,
      title:        'Why TUIs are back',
      url:          'https://example.com/post',
      author:       nil,
      published_at: '2026-05-02T12:00:00Z',
      content_html: '<p><a href="https://lobste.rs/s/abc/comments">Comments</a></p>',
      content_text: 'Comments'
    }])

    row = ArticlesStore.find_by_uid('a' * 12)
    expect(row['content_text']).to include('TUIs are back')
    expect(row['content_text']).to include('lazygit')
    expect(row['content_html']).not_to include('Comments</a>')
  end

  it 'leaves substantial bodies untouched (no upgrade needed)' do
    expect(Providers::HttpClient).not_to receive(:get)

    long_text = 'A' * 600
    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid:          'b' * 12,
      title:        'Already substantial',
      url:          'https://example.com/post-b',
      author:       nil,
      published_at: '2026-05-02T12:00:00Z',
      content_html: "<p>#{long_text}</p>",
      content_text: long_text
    }])

    row = ArticlesStore.find_by_uid('b' * 12)
    expect(row['content_text']).to eq(long_text)
  end

  it 'falls through to the original teaser when readability fails' do
    allow(Providers::HttpClient).to receive(:get).and_raise(Net::ReadTimeout)

    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid:          'c' * 12,
      title:        'Fallback case',
      url:          'https://example.com/post-c',
      author:       nil,
      published_at: '2026-05-02T12:00:00Z',
      content_html: '<p><a href="https://lobste.rs/s/xyz/comments">Comments</a></p>',
      content_text: 'Comments'
    }])

    row = ArticlesStore.find_by_uid('c' * 12)
    expect(row['content_text']).to eq('Comments')
  end

  it 'skips when the entry has no source URL' do
    expect(Providers::HttpClient).not_to receive(:get)

    ArticlesStore.import(feed_id: feed['id'], entries: [{
      uid:          'd' * 12,
      title:        'No URL',
      url:          '',
      author:       nil,
      published_at: '2026-05-02T12:00:00Z',
      content_html: '<p>Comments</p>',
      content_text: 'Comments'
    }])

    row = ArticlesStore.find_by_uid('d' * 12)
    expect(row['content_text']).to eq('Comments')
  end
end
