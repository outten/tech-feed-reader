require_relative 'spec_helper'
require_relative '../app/main'
require 'fileutils'

# The SimpleCov report references its assets under a versioned subdir
# (assets/<version>/application.css). The route must match that nested
# path (it previously only matched a single segment, so every asset
# 404'd and the report rendered unstyled). spec_helper auto-applies the
# admin Basic Auth header.
RSpec.describe 'GET /admin/coverage/assets/* (SimpleCov report assets)' do
  include Rack::Test::Methods
  def app
    TechFeedReader
  end

  assets_dir = File.expand_path('../../coverage/assets', __FILE__)
  nested     = File.join(assets_dir, 'spectest-0.0.0')

  before do
    FileUtils.mkdir_p(nested)
    File.write(File.join(nested, 'application.css'), 'body { color: red; }')
  end

  after { FileUtils.rm_rf(nested) }

  it 'serves an asset under a versioned/nested subdir with the right content type' do
    get '/admin/coverage/assets/spectest-0.0.0/application.css'
    expect(last_response.status).to eq(200)
    expect(last_response.headers['Content-Type']).to include('text/css')
    expect(last_response.body).to include('color: red')
  end

  it '404s for a missing asset' do
    get '/admin/coverage/assets/spectest-0.0.0/missing.css'
    expect(last_response.status).to eq(404)
  end

  it 'blocks path traversal out of coverage/assets' do
    get '/admin/coverage/assets/%2e%2e/%2e%2e/Gemfile'
    expect(last_response.status).not_to eq(200)
  end
end
