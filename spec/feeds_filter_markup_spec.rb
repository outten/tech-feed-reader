require_relative 'spec_helper'
require_relative '../app/main'
require_relative '../app/feeds_store'

# STUFF #27 — the actual filter behavior is client-side
# (public/feeds-filter.js), so server-side specs cover the markup
# contract: filter bars render, rows carry data-topic / data-search,
# category headings carry data-topic, the JS file is included.

RSpec.describe 'feed filter bar markup (STUFF #27)' do
  include Rack::Test::Methods
  def app; TechFeedReader; end

  describe 'subscribed feeds table' do
    it 'renders the filter bar above the table when feeds exist' do
      FeedsStore.add(url: 'https://hn.example/rss', title: 'HN', topic: 'technology')
      get '/feeds'
      expect(last_response.body).to include('data-target="feeds-table"')
      expect(last_response.body).to include('class="feeds-filter-search"')
      # All / Tech / Sports / Nature / General chips are present.
      expect(last_response.body).to include('data-topic="technology"')
      expect(last_response.body).to include('data-topic="sports"')
      expect(last_response.body).to include('data-topic="nature"')
      expect(last_response.body).to include('data-topic="general"')
    end

    it 'omits the filter bar when there are no subscribed feeds' do
      get '/feeds'
      expect(last_response.body).not_to include('data-target="feeds-table"')
    end

    it 'annotates each feed row with data-topic + data-search' do
      FeedsStore.add(url: 'https://hn.example/rss', title: 'Hacker News', topic: 'technology')
      get '/feeds'
      expect(last_response.body).to match(/<tr [^>]*data-topic="technology"/)
      expect(last_response.body).to match(/<tr [^>]*data-search="[^"]*hacker news[^"]*"/i)
    end
  end

  describe 'catalog browse' do
    it 'renders the filter bar in the Discover popular feeds section' do
      get '/feeds'
      expect(last_response.body).to include('data-target="catalog"')
      expect(last_response.body).to include('id="discover-catalog"')
    end

    it 'annotates each catalog row with data-topic / data-search / data-subscribed' do
      get '/feeds'
      expect(last_response.body).to match(/<li class="catalog-row[^"]*"[\s\S]*?data-topic="[^"]+"/)
      expect(last_response.body).to match(/data-search="[^"]+"/)
      expect(last_response.body).to match(/data-subscribed="[01]"/)
    end

    it 'annotates each category heading with its top-level data-topic' do
      get '/feeds'
      expect(last_response.body).to match(/<h4 class="catalog-category" data-topic="(technology|sports|nature)">/)
    end
  end

  it 'pulls in public/feeds-filter.js at the bottom of the page' do
    get '/feeds'
    expect(last_response.body).to include('/feeds-filter.js')
  end
end
