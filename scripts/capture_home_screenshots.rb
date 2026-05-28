#!/usr/bin/env ruby
# frozen_string_literal: true

# One-shot screenshot capture for the marketing home page feature
# cards (views/home.erb). Boots the app on a non-default port with
# the auth wall + helper methods monkey-patched to render as the first
# user in the dev DB, then drives Chrome headless to capture the
# pages we want as PNGs.
#
# Usage:
#   bundle exec ruby scripts/capture_home_screenshots.rb [page ...]
#
# With no arguments captures /youtube and /comics. Output lands in
# public/img/home/<page>.png. Process exits after the captures finish.

ENV['RACK_ENV'] ||= 'development'
require_relative '../app/main'
require 'rackup/handler'

CAPTURE_PORT = (ENV['CAPTURE_PORT'] || 4569).to_i
CHROME = ENV['CHROME_BINARY'] ||
         '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'

pages = ARGV.empty? ? %w[youtube comics] : ARGV

# Pick a user to render as. The marketing screenshots want a
# populated account — the dev DB's first user usually has the
# subscriptions and content the cards are meant to show off.
user = UsersStore.all.first
abort 'No users in dev DB — sign up at /sign-up first.' unless user

puts "Capturing as user: #{user['username']} (#{user['id']})"

# Bypass auth: helper overrides + wall off. Scoped to this process,
# so production / dev server runs are untouched.
TechFeedReader.class_eval do
  helpers do
    define_method(:current_user)    { user }
    define_method(:current_user_id) { user['id'].to_i }
    define_method(:signed_in?)      { true }
  end
end
TechFeedReader.enforce_auth_wall = false

server = Thread.new do
  Rackup::Handler.get('puma').run(TechFeedReader, Port: CAPTURE_PORT, Host: 'localhost', Silent: true)
end

# Crude wait — Puma takes ~1-2s to bind on this machine.
require 'net/http'
30.times do
  begin
    Net::HTTP.get_response(URI("http://localhost:#{CAPTURE_PORT}/health"))
    break
  rescue Errno::ECONNREFUSED
    sleep 0.2
  end
end

out_dir = File.expand_path('../public/img/home', __dir__)
Dir.mkdir(out_dir) unless Dir.exist?(out_dir)

pages.each do |page|
  out = File.join(out_dir, "#{page}.png")
  url = "http://localhost:#{CAPTURE_PORT}/#{page}"
  cmd = [
    CHROME,
    '--headless=new',
    '--disable-gpu',
    '--hide-scrollbars',
    '--no-sandbox',
    '--window-size=1280,900',
    "--screenshot=#{out}",
    url
  ]
  puts "Capturing #{url} → #{out}"
  system(*cmd, out: '/dev/null', err: '/dev/null')
  size = File.exist?(out) ? File.size(out) : 0
  puts "  wrote #{size} bytes"
end

exit 0
