require_relative 'spec_helper'
require_relative '../app/main'

RSpec.describe 'theme toggle' do
  include Rack::Test::Methods

  def app
    TechFeedReader
  end

  it 'renders the toggle button on every page' do
    %w[/admin/dashboard /topics /articles /feeds /tags /search].each do |path|
      get path
      expect(last_response.body).to include('id="theme-toggle"'), "missing on #{path}"
      expect(last_response.body).to include('Toggle light / dark theme')
    end
  end

  it 'bootstraps the theme via inline head script (no FOUC)' do
    get '/admin/dashboard'
    expect(last_response.body).to match(/Theme bootstrap.*localStorage\.getItem\('theme'\)/m)
    expect(last_response.body).to include("classList.toggle('dark', theme === 'dark')")
  end

  it 'wires the toggle handler at the bottom of body' do
    get '/admin/dashboard'
    expect(last_response.body).to include("getElementById('theme-toggle')")
    expect(last_response.body).to include("localStorage.setItem('theme'")
  end

  it 'sets data-theme="light" by default on the html element' do
    get '/admin/dashboard'
    expect(last_response.body).to include('data-theme="light"')
  end
end
