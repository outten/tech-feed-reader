require_relative 'spec_helper'
require_relative '../app/main'

RSpec.describe 'TechFeedReader smoke' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  it 'redirects / → /dashboard' do
    get '/'
    expect(last_response.status).to eq(302)
    expect(last_response.headers['Location']).to include('/dashboard')
  end

  it 'renders /dashboard' do
    get '/dashboard'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Dashboard')
  end

  %w[/articles /feeds /tags /search /admin/health /admin/cache].each do |path|
    it "renders #{path}" do
      get path
      expect(last_response.status).to eq(200)
    end
  end

  it 'renders /article/:id' do
    get '/article/abc123'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('abc123')
  end
end
