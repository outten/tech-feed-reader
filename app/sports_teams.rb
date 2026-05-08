require_relative 'feed_catalog'
require_relative 'feeds_store'

# Team identity for the /sports/team/:slug detail pages. Maps a
# slug → human-readable name + the catalog feed URLs that cover
# that team. Each team can be backed by multiple feeds (e.g. an
# RSS news source + a podcast feed for the same team).
#
# Why a hand-curated list instead of deriving from the catalog?
# A team isn't always 1:1 with a sub-category — Rugby has both
# All Blacks and Black Ferns inside the :rugby category, and
# their coverage feeds overlap (BBC + RNZ cover both). The
# user's actual mental model is team-centric ("show me Eagles
# stuff"), not category-centric, so the team layer is its own
# data shape.
#
# Adding a team: append to TEAMS. Each team's `feed_urls` must
# point at URLs already in FeedCatalog::CATALOG so the catalog
# remains the single source of truth for what's subscribable.
# `image_url` is nil for now — emoji-only — but the field is
# there so a follow-up PR can drop in real logos without a
# schema change.
module SportsTeams
  TEAMS = [
    {
      slug:       'eagles',
      name:       'Philadelphia Eagles',
      short_name: 'Eagles',
      sport:      :nfl,
      emoji:      '🦅',
      image_url:  nil,
      blurb:      'NFC East · NFL — Bleeding Green Nation news + podcast.',
      feed_urls: [
        'https://www.bleedinggreennation.com/rss/index.xml',
        'https://feeds.megaphone.fm/VMP9406149033'
      ]
    },
    {
      slug:       'sixers',
      name:       'Philadelphia 76ers',
      short_name: 'Sixers',
      sport:      :nba,
      emoji:      '🏀',
      image_url:  nil,
      blurb:      'Eastern Conference · NBA — Liberty Ballers + Sixers Talk.',
      feed_urls: [
        'https://www.libertyballers.com/rss/index.xml',
        'https://feeds.simplecast.com/jxr32ewl'
      ]
    },
    {
      slug:       'union',
      name:       'Philadelphia Union',
      short_name: 'Union',
      sport:      :soccer,
      emoji:      '⚽',
      image_url:  nil,
      blurb:      'MLS Eastern Conference — The Philly Soccer Page + All Three Points.',
      feed_urls: [
        'https://phillysoccerpage.net/feed/',
        'https://phillysoccerpage.net/category/podcasts/all-three-points/feed/'
      ]
    },
    {
      slug:       'all-blacks',
      name:       'New Zealand All Blacks (men + Black Ferns)',
      short_name: 'NZ Rugby',
      sport:      :rugby,
      emoji:      '🏉',
      image_url:  nil,
      blurb:      "All Blacks (men's) + Black Ferns (women's) — BBC, RNZ, Aotearoa Rugby Pod, GBR Aus/NZ.",
      feed_urls: [
        'https://feeds.bbci.co.uk/sport/rugby-union/rss.xml',
        'https://www.rnz.co.nz/rss/sport.xml',
        'https://feeds.acast.com/public/shows/aotearoa-rugby-pod',
        'https://feeds.megaphone.fm/GLT9898976502'
      ]
    },
    {
      slug:       'tennis',
      name:       'Tennis (ATP / WTA / Grand Slams)',
      short_name: 'Tennis',
      sport:      :tennis,
      emoji:      '🎾',
      image_url:  nil,
      blurb:      'No specific allegiance — every ATP, WTA, and Grand Slam draw worth following.',
      feed_urls: [
        'https://www.espn.com/espn/rss/tennis/news',
        'https://feeds.bbci.co.uk/sport/tennis/rss.xml',
        'https://tennis365.com/feed',
        'https://feeds.acast.com/public/shows/thetennispodcast'
      ]
    }
  ].freeze

  module_function

  def all
    TEAMS
  end

  def find(slug)
    TEAMS.find { |t| t[:slug] == slug.to_s }
  end

  def for_sport(sport)
    TEAMS.select { |t| t[:sport] == sport.to_sym }
  end

  # Resolve the user's actual subscriptions for a team — only the
  # feeds where feed_urls overlap with FeedsStore.find_by_url. Used
  # by the team detail view to render only what's subscribed (don't
  # show empty cards for catalog feeds the user hasn't added).
  def subscribed_feeds_for(team)
    return [] unless team
    team[:feed_urls].filter_map { |u| FeedsStore.find_by_url(u) }
  end
end
