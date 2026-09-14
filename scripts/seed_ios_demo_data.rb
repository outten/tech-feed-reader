#!/usr/bin/env ruby
# Populates an EXISTING account with realistic content across every
# area the iOS app covers, so manual testing in the Simulator/on-device
# has something to look at in every screen instead of an empty state.
#
# Dev tooling only — not a product feature, no /api/v1 endpoint calls
# it. Requires a user that already signed up (has a passkey + recovery
# codes) via the web /sign-up flow or the iOS app's browser hand-off;
# this script only adds content, it doesn't create accounts (same
# division of labor as scripts/seed_user.rb).
#
# Usage:
#   make seed-ios-demo USER=ios-tester
#   bundle exec ruby scripts/seed_ios_demo_data.rb ios-tester

require_relative '../app/credentials'
require_relative '../app/database'
require_relative '../app/users_store'
require_relative '../app/feeds_store'
require_relative '../app/feed_catalog'
require_relative '../app/scheduler'
require_relative '../app/articles_store'
require_relative '../app/read_state_store'
require_relative '../app/tags_store'
require_relative '../app/tags_applier'
require_relative '../app/mute_rules_store'
require_relative '../app/sports_catalog'
require_relative '../app/sports_leagues_store'
require_relative '../app/sports_teams_store'
require_relative '../app/sports_standings_store'
require_relative '../app/sports_matches_store'
require_relative '../app/sports_players_store'
require_relative '../app/sports_follows_store'
require_relative '../app/stock_follows_store'
require_relative '../app/stock_quotes_store'
require_relative '../app/stock_news_feed'
require_relative '../app/radio_catalog'
require_relative '../app/radio_store'
require_relative '../app/digests'
require_relative '../app/digest_store'
require_relative '../app/triage/claude'
require_relative '../app/triage_store'

Database.migrate!

username = ARGV[0] || ENV['USER_USERNAME']
if username.to_s.strip.empty?
  abort 'Usage: bundle exec ruby scripts/seed_ios_demo_data.rb <username> (the user must already exist — sign up first)'
end

user = UsersStore.find_by_username(username)
unless user
  abort "No user '#{username}'. Sign up first (via /sign-up, or the iOS app's sign-up hand-off), then re-run this."
end

puts "Seeding demo data for user ##{user['id']} (#{user['username']})"

# ---- 1. Feeds — one real catalog URL per area the app has a dedicated
# screen for, then a REAL fetch so content/images are genuine. -----------
CATALOG_URLS = [
  'https://news.ycombinator.com/rss',                                            # Feeds / Articles
  'https://changelog.com/podcast/feed',                                          # Podcasts
  'https://www.youtube.com/feeds/videos.xml?channel_id=UCwmZiChSryoWQCZMIQezgTg', # YouTube
  'https://xkcd.com/atom.xml',                                                   # Comics
  'https://feeds.npr.org/1001/rss.xml',                                          # NPR
  'https://www.pbs.org/newshour/feeds/rss/headlines'                             # PBS
].freeze

feeds = CATALOG_URLS.filter_map do |catalog_url|
  entry = FeedCatalog.find_by_url(catalog_url)
  next puts("  skip (not in catalog): #{catalog_url}") unless entry
  feed, = FeedsStore.add_for_user(
    user_id: user['id'], url: entry[:url], title: entry[:title],
    topic: FeedCatalog.topic_for(entry).to_s
  )
  feed
end

puts "Subscribed to #{feeds.length} feeds — fetching real content (this hits the real internet):"
feeds.each do |feed|
  result, imported = Scheduler.refresh_one(feed)
  puts "  #{feed['title']}: #{result.status} (+#{imported})"
end

# ---- 2. Read-state variety + a tag rule + a mute rule ------------------
hn_feed = feeds.find { |f| f['url'] == 'https://news.ycombinator.com/rss' }
if hn_feed
  articles = ArticlesStore.for_feed(user['id'], hn_feed['id'], limit: 10)
  read_count = articles.first(3).each { |a| ReadStateStore.mark_read(user['id'], a['id'], read: true) }.length
  bookmarked = Array(articles[3, 2]).each { |a| ReadStateStore.mark_bookmarked(user['id'], a['id'], value: true) }.length
  puts "Marked #{read_count} read, #{bookmarked} bookmarked on Hacker News"
end

tag = TagsStore.add(user_id: user['id'], name: 'AI', match_kind: 'keyword', match_value: 'AI')
tagged = TagsApplier.apply_to_existing(tag)
puts "Added tag 'AI' (matched #{tagged} existing articles)"

MuteRulesStore.add(user_id: user['id'], kind: 'keyword', value: 'cryptocurrency')
puts "Added a mute rule (keyword: cryptocurrency)"

# ---- 3. Sports — follow a team (with seeded standings + matches so the
# detail screen has something without waiting on a live ESPN sync), its
# league, and a notable-player chip. Mirrors ensure_catalog_team_in_db /
# ensure_catalog_league_in_db in app/main.rb (private Sinatra helpers,
# not callable outside a request — reimplemented here against the same
# store methods). ---------------------------------------------------------
def materialize_catalog_team!(slug)
  team = SportsCatalog.find_team(slug)
  return [nil, nil] unless team
  league = SportsCatalog.find_league(team[:sport_slug], team[:league_slug])
  return [nil, nil] unless league

  league_row = SportsLeaguesStore.upsert(
    slug: league[:slug], name: league[:name], sport: league[:sport],
    source_provider: league[:source_provider] || 'catalog',
    external_id: league[:external_id] || league[:slug], country: league[:country]
  )
  team_row = SportsTeamsStore.upsert(
    league_id: league_row['id'], slug: team[:slug], name: team[:name],
    short_name: team[:short_name], location: team[:location], image_url: team[:image_url],
    source_provider: team[:source_provider] || 'catalog', external_id: team[:external_id] || team[:slug]
  )
  [league_row, team_row]
end

league_row, eagles = materialize_catalog_team!('eagles')
if eagles
  SportsFollowsStore.add(user_id: user['id'], kind: 'team', value: 'eagles')
  SportsFollowsStore.add(user_id: user['id'], kind: 'league', value: league_row['slug'])
  SportsStandingsStore.upsert(
    league_id: league_row['id'], team_id: eagles['id'], group_name: 'NFC East',
    source_provider: 'seed', position: 1, wins: 10, losses: 3, ties: 0
  )
  SportsMatchesStore.upsert(
    league_id: league_row['id'], source_provider: 'seed', external_id: 'seed-upcoming',
    scheduled_at: (Time.now.utc + 3 * 24 * 3600).iso8601, status: 'scheduled', home_team_id: eagles['id']
  )
  SportsMatchesStore.upsert(
    league_id: league_row['id'], source_provider: 'seed', external_id: 'seed-final',
    scheduled_at: (Time.now.utc - 3 * 24 * 3600).iso8601, status: 'final',
    home_team_id: eagles['id'], home_score: 27, away_score: 20
  )
  puts "Followed Eagles + NFL, seeded standings/matches"
end

team_with_players = SportsCatalog.all_teams.find { |t| (t[:players] || []).any? }
if team_with_players
  player_name = team_with_players[:players].first
  slug = "#{team_with_players[:slug]}-#{player_name.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-+|-+$/, '')}"
  player_league = SportsCatalog.find_league(team_with_players[:sport_slug], team_with_players[:league_slug])
  player = SportsPlayersStore.upsert(sport: player_league[:sport], slug: slug, full_name: player_name,
                                    source_provider: 'catalog', external_id: slug)
  SportsFollowsStore.add(user_id: user['id'], kind: 'player', value: slug)
  puts "Followed player #{player['full_name']}"
end

# ---- 4. Stocks — follow 2 symbols, seed quotes (no FINNHUB_API_KEY
# needed), subscribe + fetch real news for each. -------------------------
{ 'AAPL' => 'Apple Inc', 'MSFT' => 'Microsoft Corp' }.each do |symbol, name|
  StockFollowsStore.add(user_id: user['id'], symbol: symbol, name: name)
  StockQuotesStore.upsert(symbol: symbol, name: name, price: 150.0, change: 1.2, change_pct: 0.8)
  feed = StockNewsFeed.ensure_feed!(symbol, name)
  FeedsStore.subscribe(user['id'], feed['id'])
  result, imported = Scheduler.refresh_one(feed)
  puts "Followed #{symbol} — news feed #{result.status} (+#{imported})"
end

# ---- 5. Radio — follow a couple of stations. ---------------------------
RadioStore.seed_catalog!
RadioStore.all_stations.first(2).each { |station| RadioStore.follow!(user['id'], station['id']) }
puts "Followed 2 radio stations"

# ---- 6. Digest (always) + Triage (only if Claude is configured). -------
_id, digest_result = Digests.generate_and_store!(user['id'])
puts "Generated a digest (#{digest_result.count} articles)"

if Triage::Claude.available?
  result = Triage::Claude.run(user['id'])
  TriageStore.create(user['id'], result) if result.status != :unavailable
  puts "Ran triage: #{result.status}"
else
  puts "Skipped triage (ANTHROPIC_API_KEY not set) — not an error, just nothing to seed there"
end

puts "\nDone. Log into the iOS app as '#{user['username']}' to see it."
