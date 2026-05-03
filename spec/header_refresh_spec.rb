require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'

RSpec.describe 'header refresh button' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  it 'renders the refresh form on every page' do
    %w[/dashboard /topics /articles /feeds /tags /search /admin/cache /admin/health].each do |path|
      get path
      expect(last_response.body).to include('id="header-refresh"'), "missing on #{path}"
      expect(last_response.body).to include('action="/admin/refresh/all"')
      expect(last_response.body).to include('Refresh all feeds')
    end
  end

  it 'still hits the existing POST /admin/refresh/all flow when clicked' do
    FeedsStore.add(url: 'https://example.com/feed.rss', title: 'Example')
    response = instance_double(Net::HTTPSuccess, code: '304', body: '')
    allow(response).to receive(:[]) { |_| nil }
    allow(Providers::HttpClient).to receive(:get).and_return(response)

    post '/admin/refresh/all'
    expect(last_response.status).to eq(302)
    expect(last_response.headers['Location']).to include('/feeds?notice=refreshed-all')
  end
end
