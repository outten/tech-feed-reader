source 'https://rubygems.org'

# Web framework
gem 'sinatra'
gem 'puma'
gem 'rerun'

# Test
group :test do
  gem 'rspec'
  gem 'rack-test'
end

# Config
gem 'dotenv'
gem 'ostruct'

# Feed parsing — feedjira normalises RSS 2.0 / RSS 1.0 / Atom into a single
# shape so we don't ship three parsers. Pulls in nokogiri as a dependency.
gem 'feedjira'

# HTML sanitization for the reading view — strip <script>, <iframe>,
# on-* event handlers before rendering article content.
gem 'loofah'

# csv is no longer a default gem starting with Ruby 3.4; needed if/when we
# add export endpoints. Cheap to ship now so it's there when Tier 3 lands.
gem 'csv'
