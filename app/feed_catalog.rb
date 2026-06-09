require_relative 'feeds_store'

# A curated catalog of 25 popular tech feeds, grouped by category.
# Powers the "Discover popular feeds" section on /feeds — each entry
# becomes a one-click Add button. Already-subscribed URLs render as
# "✓ Subscribed" so re-adds are blocked at the UI layer.
#
# Same data structure also seeds the default 5-feed install via
# scripts/seed_feeds.rb, which picks the ones flagged `seed: true`
# below.
#
# Updating the catalog: append to CATALOG (don't reorder existing
# entries — the view groups by `category` and orders within each
# category by insertion). Verify the URL parses by visiting it in a
# browser before merging.
module FeedCatalog
  # Top-level grouping. Mirrors `feeds.topic` in the DB. Used by
  # /articles?topic= filters and the catalog UI's section split.
  TOPICS = {
    technology: 'Technology',
    sports:     'Sports',
    nature:     'Nature & Documentary',
    humor:      'Humor',
    finance:    'Finance & Markets',
    world_news: 'World News',
    science:    'Science',
    gaming:     'Gaming',
    food:       'Food & Cooking',
    # STUFF #89
    npr:        'NPR',
    pbs:        'PBS'
  }.freeze

  # Sub-grouping inside a topic. Used as the H4 headings within the
  # catalog browse list on /feeds.
  CATEGORIES = {
    # Technology
    aggregator:  'Aggregators',
    publisher:   'Tech publishers',
    engineering: 'Engineering blogs',
    ai:          'AI / ML',
    # STUFF.md #18 — :security renamed → :cyber for broader cyber-
    # security coverage. The DB stores feeds.topic, not the category
    # symbol, so this is a code-only rename.
    cyber:       'Cyber security',
    development: 'Software development',
    personal:    'Personal blogs',
    podcast:     'Podcasts',
    # Sports (Phase S2 + STUFF #52)
    nfl:           'NFL',
    nba:           'NBA / Basketball',
    soccer:        'Soccer',
    rugby:         'Rugby',
    tennis:        'Tennis',
    cricket:       'Cricket',
    baseball:      'Baseball',
    golf:          'Golf',
    motorsport:    'Motorsport (F1 / NASCAR / IndyCar)',
    badminton:     'Badminton',
    horse_racing:  'Horse Racing',
    # STUFF.md #16 — nature / documentary YouTube channels
    youtube_nature: 'Nature & wildlife (YouTube)',
    # Phase 2 follow-up (2026-05-12) — sports YouTube channels so
    # game highlights / league channels surface in /whats-on's "To
    # watch today" alongside nature.
    youtube_sports: 'Sports (YouTube)',
    # STUFF.md #18 — mythology / classical history (Greek / Roman / Norse).
    mythos:      'Mythology & classical history',
    # STUFF #65 — daily-ish webcomics + humor (xkcd, SMBC, Oatmeal, etc.).
    webcomics:   'Webcomics & humor',
    # Finance & Markets (STUFF #85)
    markets_news:  'Market news',
    # World News (STUFF #85)
    world:         'World news',
    # Science (STUFF #85)
    science_pub:   'Science publishers',
    space:         'Space & astronomy',
    # Gaming (STUFF #85)
    gaming_pub:    'Gaming publishers',
    # Food & Cooking (STUFF #88)
    food_recipes:  'Recipe blogs & cooking',
    food_news:     'Food journalism',
    food_podcasts: 'Food podcasts',
    # NPR & PBS (STUFF #89)
    npr_news:      'NPR News',
    npr_podcasts:  'NPR Podcasts',
    pbs_news:      'PBS NewsHour',
    pbs_shows:     'PBS Shows & Documentaries'
  }.freeze

  # Map each sub-category to its top-level topic. Avoids duplicating
  # `:topic => :technology` on every existing catalog entry — the
  # derivation is single-sourced here. New categories must add a
  # row or `topic_for` will raise.
  CATEGORY_TO_TOPIC = {
    aggregator:  :technology,
    publisher:   :technology,
    engineering: :technology,
    ai:          :technology,
    cyber:       :technology,
    development: :technology,
    personal:    :technology,
    podcast:     :technology,
    nfl:           :sports,
    nba:           :sports,
    soccer:        :sports,
    rugby:         :sports,
    tennis:        :sports,
    cricket:       :sports,
    baseball:      :sports,
    golf:          :sports,
    motorsport:    :sports,
    badminton:     :sports,
    horse_racing:  :sports,
    youtube_nature: :nature,
    youtube_sports: :sports,
    mythos:      :technology,
    webcomics:   :humor,
    markets_news:  :finance,
    world:         :world_news,
    science_pub:   :science,
    space:         :science,
    gaming_pub:    :gaming,
    food_recipes:  :food,
    food_news:     :food,
    food_podcasts: :food,
    npr_news:      :npr,
    npr_podcasts:  :npr,
    pbs_news:      :pbs,
    pbs_shows:     :pbs
  }.freeze

  CATALOG = [
    # ---- aggregators (2) ----------------------------------------------
    { url: 'https://news.ycombinator.com/rss', title: 'Hacker News', category: :aggregator,
      interval: FeedsStore::HIGH_FREQUENCY_INTERVAL, seed: true,
      blurb: 'Front page of the tech industry — fast-moving link aggregator.' },
    { url: 'https://lobste.rs/rss', title: 'Lobsters', category: :aggregator,
      interval: FeedsStore::HIGH_FREQUENCY_INTERVAL, seed: true,
      blurb: 'Programmer-curated link aggregator with a comments culture.' },

    # ---- mainstream tech publishers (8) -------------------------------
    { url: 'https://feeds.arstechnica.com/arstechnica/index', title: 'Ars Technica', category: :publisher,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: true,
      blurb: 'In-depth tech and science journalism.' },
    { url: 'https://www.theverge.com/rss/index.xml', title: 'The Verge', category: :publisher,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: true,
      blurb: 'Consumer tech, gadgets, and culture.' },
    { url: 'https://techcrunch.com/feed/', title: 'TechCrunch', category: :publisher,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Startup news, product launches, fundraising.' },
    { url: 'https://www.wired.com/feed/rss', title: 'Wired', category: :publisher,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Tech, science, culture, and policy.' },
    { url: 'https://www.theregister.com/headlines.atom', title: 'The Register', category: :publisher,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'British IT news with a sharp angle.' },
    { url: 'https://www.technologyreview.com/feed/', title: 'MIT Technology Review', category: :publisher,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Long-form research and policy coverage.' },
    { url: 'https://www.engadget.com/rss.xml', title: 'Engadget', category: :publisher,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Daily consumer tech news and reviews.' },
    { url: 'https://www.404media.co/rss/', title: '404 Media', category: :publisher,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Independent reporter-owned tech investigations.' },

    # ---- company engineering blogs (5) --------------------------------
    { url: 'https://blog.cloudflare.com/rss/', title: 'Cloudflare Blog', category: :engineering,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Networks, security, edge compute deep-dives.' },
    { url: 'https://github.blog/feed/', title: 'GitHub Blog', category: :engineering,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Engineering, security, and product posts from GitHub.' },
    { url: 'https://stripe.com/blog/feed.rss', title: 'Stripe Blog', category: :engineering,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Payments engineering and developer tooling.' },
    { url: 'https://netflixtechblog.com/feed', title: 'Netflix Tech Blog', category: :engineering,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Streaming platform infrastructure at Netflix.' },
    { url: 'https://aws.amazon.com/blogs/aws/feed/', title: 'AWS News Blog', category: :engineering,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Service launches and architecture posts from AWS.' },

    # ---- AI / ML (3) --------------------------------------------------
    { url: 'https://huggingface.co/blog/feed.xml', title: 'Hugging Face Blog', category: :ai,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Models, datasets, training techniques, community news.' },
    { url: 'https://thegradient.pub/rss/', title: 'The Gradient', category: :ai,
      interval: FeedsStore::PERSONAL_BLOG_INTERVAL, seed: false,
      blurb: 'Long-form AI research perspectives and interviews.' },
    { url: 'https://magazine.sebastianraschka.com/feed', title: 'Sebastian Raschka', category: :ai,
      interval: FeedsStore::PERSONAL_BLOG_INTERVAL, seed: false,
      blurb: 'Practical ML / LLM essays from a researcher-educator.' },

    # ---- cyber security (6) -------------------------------------------
    # STUFF.md #18 — :security renamed → :cyber. Existing three feeds
    # moved under the new category; three new feeds added for more
    # operational/news cyber coverage.
    { url: 'https://krebsonsecurity.com/feed/', title: 'Krebs on Security', category: :cyber,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Investigative reporting on cybercrime and breaches.' },
    { url: 'https://www.schneier.com/feed/atom/', title: 'Schneier on Security', category: :cyber,
      interval: FeedsStore::PERSONAL_BLOG_INTERVAL, seed: false,
      blurb: 'Bruce Schneier on security, privacy, and policy.' },
    { url: 'https://www.bleepingcomputer.com/feed/', title: 'Bleeping Computer', category: :cyber,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Daily breach disclosures and malware analysis.' },
    { url: 'https://www.darkreading.com/rss.xml', title: 'Dark Reading', category: :cyber,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Enterprise infosec news — threats, vulnerabilities, defense.' },
    { url: 'https://thehackernews.com/feeds/posts/default', title: 'The Hacker News', category: :cyber,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Fast-moving daily coverage of vulnerabilities, exploits, and breaches.' },
    { url: 'https://www.csoonline.com/feed/', title: 'CSO Online', category: :cyber,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'CISO-perspective coverage — strategy, governance, risk, IR.' },

    # ---- software development (5) -------------------------------------
    # STUFF.md #18. Distinct from :engineering (which is company eng-
    # blog content) — this is the "thinking about how to write code"
    # genre: Fowler patterns, Spolsky business-of-software, A List
    # Apart on the craft, CSS-Tricks for frontend, Atwood for the
    # culture. All verified live on 2026-05-11.
    { url: 'https://martinfowler.com/feed.atom', title: 'Martin Fowler', category: :development,
      interval: FeedsStore::PERSONAL_BLOG_INTERVAL, seed: false,
      blurb: 'Patterns, refactoring, architecture — Fowler\'s long-running thinking blog.' },
    { url: 'https://www.joelonsoftware.com/feed/', title: 'Joel on Software', category: :development,
      interval: FeedsStore::PERSONAL_BLOG_INTERVAL, seed: false,
      blurb: 'Joel Spolsky on the business + craft of building software.' },
    { url: 'https://alistapart.com/main/feed/', title: 'A List Apart', category: :development,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Long-form essays on web design, accessibility, and frontend craft.' },
    { url: 'https://css-tricks.com/feed/', title: 'CSS-Tricks', category: :development,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Frontend, CSS, and the wider web platform — practical how-tos.' },
    { url: 'https://blog.codinghorror.com/rss/', title: 'Coding Horror', category: :development,
      interval: FeedsStore::PERSONAL_BLOG_INTERVAL, seed: false,
      blurb: 'Jeff Atwood (Stack Overflow co-founder) on programming and developer culture.' },

    # ---- mythology & classical history (4) ---------------------------
    # STUFF.md #18 — mythos. Greek / Roman / Norse mythology and the
    # adjacent classical-history / philosophy corner. Mix of essay
    # publishers and podcasts. Verified live 2026-05-11.
    { url: 'https://aeon.co/feed.rss', title: 'Aeon', category: :mythos,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Long-form essays on philosophy, classics, and mythology among other areas.' },
    { url: 'https://dailystoic.com/feed/', title: 'Daily Stoic', category: :mythos,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Ryan Holiday — daily reflections drawn from Roman / Greek Stoic philosophy.' },
    { url: 'https://feeds.feedburner.com/mythsandlegends', title: 'Myths and Legends', category: :mythos,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Jason Weiser\'s podcast retelling classical Greek, Norse, and global myths.' },
    { url: 'https://omny.fm/shows/stuff-you-missed-in-history-class/playlists/podcast.rss',
      title: 'Stuff You Missed in History Class', category: :mythos,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'iHeart Media\'s long-running history podcast — mythology, ancient world, and lesser-known stories.' },

    # ---- personal blogs (4) -------------------------------------------
    { url: 'https://simonwillison.net/atom/everything/', title: 'Simon Willison', category: :personal,
      interval: FeedsStore::PERSONAL_BLOG_INTERVAL, seed: true,
      blurb: 'AI tooling, Python, web, and curated link blogging.' },
    { url: 'https://jvns.ca/atom.xml', title: 'Julia Evans', category: :personal,
      interval: FeedsStore::PERSONAL_BLOG_INTERVAL, seed: false,
      blurb: 'Approachable deep-dives on systems and debugging.' },
    { url: 'https://danluu.com/atom.xml', title: 'Dan Luu', category: :personal,
      interval: FeedsStore::PERSONAL_BLOG_INTERVAL, seed: false,
      blurb: 'Long, data-driven essays on engineering and orgs.' },
    { url: 'https://ciechanow.ski/atom.xml', title: 'Bartosz Ciechanowski', category: :personal,
      interval: FeedsStore::PERSONAL_BLOG_INTERVAL, seed: false,
      blurb: 'Interactive technical explainers (rare, exceptional posts).' },

    # ---- podcasts (15) ------------------------------------------------
    # All ship audio enclosures (parsed by FeedParser into audio_url etc.)
    # so the article view renders the player. Most include itunes:duration
    # so the runtime shows immediately, before <audio> loads metadata.
    #
    # The catalog deliberately spans tech, news, culture, and audio drama
    # — the user's reading interests aren't purely technology, and the
    # show grouping on /podcasts works just as well across genres. Add
    # new entries near a thematic neighbour so the catalog reads as a
    # curated list rather than a dump.

    # tech-side
    { url: 'https://changelog.com/podcast/feed', title: 'The Changelog', category: :podcast,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Long-running interviews with people building the open source world.' },
    { url: 'https://audioboom.com/channels/5166624.rss', title: 'Software Engineering Daily', category: :podcast,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Daily technical interviews on infrastructure, languages, and platforms.' },
    { url: 'https://api.substack.com/feed/podcast/1517410.rss', title: 'Latent Space', category: :podcast,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Engineering-focused conversations on the AI / LLM stack.' },
    { url: 'https://api.substack.com/feed/podcast/69345.rss', title: 'Dwarkesh Podcast', category: :podcast,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Deeply researched long-form interviews — AI scaling, supply chains, history of science.' },
    { url: 'https://lexfridman.com/feed/podcast/', title: 'Lex Fridman Podcast', category: :podcast,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Long-form interviews with technologists, scientists, and public figures.' },
    { url: 'https://softskills.audio/feed.xml', title: 'Soft Skills Engineering', category: :podcast,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Weekly listener-question advice on the non-code side of engineering.' },
    { url: 'https://publicfeeds.net/f/5901/gadget-lab', title: 'Uncanny Valley (WIRED)', category: :podcast,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'WIRED on the people, power, and influence shaping Silicon Valley.' },
    { url: 'https://feeds.simplecast.com/l2i9YnTd', title: 'Hard Fork', category: :podcast,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Casey Newton and Kevin Roose making sense of the rapidly changing tech landscape (NYT).' },

    # business / tech histories
    { url: 'https://feeds.transistor.fm/acquired', title: 'Acquired', category: :podcast,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Deep, multi-hour business histories of major tech companies and deals.' },

    # news + ideas
    { url: 'https://podcasts.files.bbci.co.uk/p02nq0gn.rss', title: 'BBC Global News Podcast', category: :podcast,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'BBC twice-daily roundup of breaking world news and current affairs.' },
    { url: 'https://feeds.simplecast.com/Sl5CSM3S', title: 'The Daily (NYT)', category: :podcast,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Twenty-minute morning briefing on the biggest story of the day, from The New York Times.' },
    { url: 'https://feeds.simplecast.com/kEKXbjuJ', title: 'The Ezra Klein Show', category: :podcast,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'NYT long-form conversations on politics, ideas, and the systems that shape them.' },

    # culture + design
    { url: 'https://feeds.simplecast.com/BqbsxVfO', title: '99% Invisible', category: :podcast,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Roman Mars on the unnoticed design and architecture that shapes the world around us.' },

    # film + tv
    { url: 'https://feeds.acast.com/public/shows/690bb0b92f5fdede3448a770', title: 'What Went Wrong', category: :podcast,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'The behind-the-scenes drama of Hollywood productions — flops, near-misses, and chaos.' },

    # audio drama
    { url: 'https://starshipexcelsior.com/ExcelsiorRSS.rss', title: 'Starship Excelsior', category: :podcast,
      interval: FeedsStore::PERSONAL_BLOG_INTERVAL, seed: false,
      blurb: 'Long-running Star Trek fan audio drama — full-cast adventures aboard the USS Excelsior.' },

    # ============================================================
    # Sports (Phase S2)
    # ============================================================
    # Curated to the user's specific interests: Philadelphia teams
    # (Eagles / Sixers / Union), New Zealand rugby (All Blacks +
    # Black Ferns coverage), and tennis broadly. Each URL was
    # verified live (HTTP 200 + valid RSS/Atom signature) at the
    # time of seed. None marked seed:true — sports adoption is
    # opt-in via /feeds, not auto-installed.

    # NFL — Philadelphia Eagles
    { url: 'https://www.bleedinggreennation.com/rss/index.xml', title: 'Bleeding Green Nation', category: :nfl,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: "SB Nation's Philadelphia Eagles community — beat-writer coverage, game previews, draft analysis." },

    # NBA — Philadelphia 76ers
    { url: 'https://www.libertyballers.com/rss/index.xml', title: 'Liberty Ballers', category: :nba,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: "SB Nation's Philadelphia 76ers community — game recaps, trade analysis, roster moves." },

    # MLS — Philadelphia Union (and US/world soccer context)
    { url: 'https://phillysoccerpage.net/feed/', title: 'The Philly Soccer Page', category: :soccer,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Independent Philadelphia Union coverage — match previews, recaps, podcast episodes.' },

    # Rugby — All Blacks + Black Ferns + world rugby
    { url: 'https://feeds.bbci.co.uk/sport/rugby-union/rss.xml', title: 'BBC Rugby Union', category: :rugby,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'BBC Sport rugby union — All Blacks, Black Ferns, Six Nations, World Cup coverage.' },
    { url: 'https://www.rnz.co.nz/rss/sport.xml', title: 'RNZ Sport', category: :rugby,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: "Radio New Zealand sport — All Blacks-heavy coverage from NZ's national broadcaster." },

    # Tennis — ATP / WTA / Grand Slams
    { url: 'https://www.espn.com/espn/rss/tennis/news', title: 'ESPN Tennis', category: :tennis,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'ATP, WTA, and Grand Slam tournament coverage from ESPN.' },
    { url: 'https://feeds.bbci.co.uk/sport/tennis/rss.xml', title: 'BBC Tennis', category: :tennis,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'BBC Sport tennis — Wimbledon-heavy with ATP/WTA tour coverage year-round.' },
    { url: 'https://tennis365.com/feed', title: 'Tennis365', category: :tennis,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Independent tennis site — daily player news, tour gossip, match analysis.' },

    # ---- sports podcasts ---------------------------------------
    # Tagged with the sport's sub-category (not :podcast) so they
    # surface in the sport's section on /sports. The audio
    # enclosures still flow through FeedParser → audio_url, so the
    # global mini-player picks them up the same as tech podcasts.

    # NFL — Eagles
    { url: 'https://feeds.megaphone.fm/VMP9406149033', title: 'Bleeding Green Nation Podcast', category: :nfl,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Multi-show audio network from BGN — beat-writer interviews, post-game reactions, draft analysis.' },

    # NBA — Sixers
    { url: 'https://feeds.simplecast.com/jxr32ewl', title: 'Sixers Talk', category: :nba,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'NBC Sports Philadelphia 76ers podcast — game previews, reactions, roster news.' },

    # MLS — Union
    { url: 'https://phillysoccerpage.net/category/podcasts/all-three-points/feed/', title: 'All Three Points', category: :soccer,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: "Philly Soccer Page's flagship podcast — Philadelphia Union match recaps and analysis." },

    # Rugby — All Blacks + Black Ferns + Super Rugby
    { url: 'https://feeds.acast.com/public/shows/aotearoa-rugby-pod', title: 'Aotearoa Rugby Pod', category: :rugby,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: "Ross Karl, James Parsons + Bryn Hall on NZ rugby — All Blacks, Black Ferns, Super Rugby Pacific, NPC." },
    { url: 'https://feeds.megaphone.fm/GLT9898976502', title: 'The Good, The Bad & The Rugby (Aus/NZ)', category: :rugby,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Australian/NZ-focused rugby chat from the international podcast network.' },

    # Tennis
    { url: 'https://feeds.acast.com/public/shows/thetennispodcast', title: 'The Tennis Podcast', category: :tennis,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'David Law (BBC) + Catherine Whitaker (Eurosport) covering ATP, WTA, and all four Grand Slams.' },

    # ============================================================
    # STUFF #52 PR3 — sports breadth feeds keyed to SportsCatalog
    # leagues. Each URL is BBC Sport, ESPN, or a league-official
    # source — long-stable hosts where the per-sport RSS path is
    # well-known. Bound to SportsCatalog leagues via the
    # SPORTS_LEAGUE_FEEDS map below.
    # ============================================================

    # Soccer — global tier
    { url: 'https://feeds.bbci.co.uk/sport/football/premier-league/rss.xml',
      title: 'BBC Sport — Premier League', category: :soccer,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'BBC Sport coverage of the English top flight.' },
    { url: 'https://feeds.bbci.co.uk/sport/football/womens/rss.xml',
      title: "BBC Sport — Women's Football", category: :soccer,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'WSL, Lionesses, international women\'s football.' },
    { url: 'https://feeds.bbci.co.uk/sport/football/european/rss.xml',
      title: 'BBC Sport — European Football', category: :soccer,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'La Liga, Serie A, Bundesliga, Ligue 1 + Champions League.' },
    { url: 'https://feeds.bbci.co.uk/sport/football/african/rss.xml',
      title: 'BBC Sport — African Football', category: :soccer,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'CAF Africa Cup of Nations, AFCON, club football across the continent.' },

    # Cricket
    { url: 'https://feeds.bbci.co.uk/sport/cricket/rss.xml',
      title: 'BBC Sport — Cricket', category: :cricket,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'England, women\'s cricket, ICC tournaments + The Hundred.' },
    { url: 'https://www.espn.com/espn/rss/cricinfo/news',
      title: 'ESPNcricinfo', category: :cricket,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Global cricket coverage — Tests, ODIs, T20s, all major leagues.' },

    # Baseball
    { url: 'https://www.espn.com/espn/rss/mlb/news',
      title: 'ESPN MLB', category: :baseball,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Major League Baseball news + analysis from ESPN.' },
    { url: 'https://feeds.bbci.co.uk/sport/baseball/rss.xml',
      title: 'BBC Sport — Baseball', category: :baseball,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'BBC global baseball coverage — MLB, international, occasional NPB/KBO.' },
    # STUFF #52.3 — KBO + NPB English-language sources. KBO has a
    # dedicated independent site; NPB English coverage is sparse, so
    # the bridge falls back to the broader BBC/ESPN baseball feeds.
    { url: 'https://mykbo.net/feed/',
      title: 'MyKBO — Korea Baseball Organization', category: :baseball,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'KBO-specific English coverage — daily recaps, standings, roster moves.' },
    { url: 'https://en.yna.co.kr/RSS/sports.xml',
      title: 'Yonhap News — Korean Sports', category: :baseball,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Korean sports news (KBO baseball, K-League soccer, Olympics) from Yonhap.' },

    # Badminton — BWF is the global federation; Badzine is the
    # established independent badminton news site. Both are stable
    # English-language sources and cover men\'s + women\'s singles +
    # doubles tournaments.
    { url: 'https://bwfbadminton.com/news/feed/',
      title: 'BWF Badminton — Official', category: :badminton,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Official BWF news — World Tour, World Championships, Olympics, Sudirman Cup.' },
    { url: 'https://www.badzine.net/feed/',
      title: 'Badzine', category: :badminton,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Independent badminton journalism — interviews, tournament recaps, opinion.' },

    # Golf
    { url: 'https://www.espn.com/espn/rss/golf/news',
      title: 'ESPN Golf', category: :golf,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'PGA Tour, LPGA, DP World Tour, majors.' },
    { url: 'https://feeds.bbci.co.uk/sport/golf/rss.xml',
      title: 'BBC Sport — Golf', category: :golf,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'UK-side golf coverage; majors and Ryder Cup heavy.' },

    # Motorsport
    { url: 'https://feeds.bbci.co.uk/sport/formula1/rss.xml',
      title: 'BBC Sport — Formula 1', category: :motorsport,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'F1 race weekends, driver moves, team news.' },
    { url: 'https://www.espn.com/espn/rss/rpm/news',
      title: 'ESPN Motorsport', category: :motorsport,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'NASCAR + IndyCar + Formula 1 from ESPN.' },

    # Basketball — WNBA
    { url: 'https://www.espn.com/espn/rss/wnba/news',
      title: 'ESPN WNBA', category: :nba,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'WNBA news, game recaps, player moves.' },
    { url: 'https://www.espn.com/espn/rss/nba/news',
      title: 'ESPN NBA', category: :nba,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'NBA news + columns from ESPN.' },

    # Horse Racing
    { url: 'https://feeds.bbci.co.uk/sport/horse-racing/rss.xml',
      title: 'BBC Sport — Horse Racing', category: :horse_racing,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'UK flat + jumps coverage; Royal Ascot, Cheltenham, Grand National.' },

    # NFL (additional general source)
    { url: 'https://www.espn.com/espn/rss/nfl/news',
      title: 'ESPN NFL', category: :nfl,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'NFL news + analysis from ESPN.' },

    # MLS (additional general source)
    { url: 'https://www.espn.com/espn/rss/soccer/news',
      title: 'ESPN Soccer', category: :soccer,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Global soccer coverage from ESPN — MLS, EPL, La Liga, international.' },

    # ---- Nature & Documentary (YouTube) -------------------------------
    # STUFF.md #16. YouTube exposes a standard Atom feed per channel at
    # /feeds/videos.xml?channel_id=UC... — FeedParser handles this with
    # no special-casing. Channel IDs verified via curl 2026-05-10.
    { url: 'https://www.youtube.com/feeds/videos.xml?channel_id=UCwmZiChSryoWQCZMIQezgTg',
      title: 'BBC Earth (YouTube)', category: :youtube_nature,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'BBC Earth — Planet Earth / Frozen Planet / Blue Planet / Life clips and full segments.' },
    { url: 'https://www.youtube.com/feeds/videos.xml?channel_id=UCdsOTr6SmDrxuWE7sJFrkhQ',
      title: 'BBC Earth Science (YouTube)', category: :youtube_nature,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'BBC Earth Science — geology, weather, and the planet itself.' },
    { url: 'https://www.youtube.com/feeds/videos.xml?channel_id=UCpVm7bg6pXKo1Pr6k5kxG9A',
      title: 'National Geographic (YouTube)', category: :youtube_nature,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Nat Geo — wildlife, exploration, science, and culture from the magazine + TV network.' },
    { url: 'https://www.youtube.com/feeds/videos.xml?channel_id=UCkzTTu69cSxxab41OHrBfvQ',
      title: 'Nature on PBS (YouTube)', category: :youtube_nature,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'PBS Nature — long-form wildlife documentaries, full episodes, and behind-the-scenes.' },
    { url: 'https://www.youtube.com/feeds/videos.xml?channel_id=UCG5_BraUMNcluZPZ__oOeKg',
      title: 'Natural World Facts (YouTube)', category: :youtube_nature,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Natural World Facts — short, well-narrated wildlife / biology essays.' },
    { url: 'https://www.youtube.com/feeds/videos.xml?channel_id=UCQtW2oz8ec8pHjjxawujNjg',
      title: 'Free Documentary - Nature (YouTube)', category: :youtube_nature,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Free Documentary (Nature channel) — full-length nature documentaries reposted with permission.' },

    # ---- Sports (YouTube, 7) ------------------------------------------
    # Phase 2 follow-up (2026-05-12). Game highlights + league channels
    # so the "To watch today" section on / surfaces sports clips, not
    # just nature docs. All channel IDs verified live via curl on
    # 2026-05-12 (and the channel-feed URL returns HTTP 200).
    { url: 'https://www.youtube.com/feeds/videos.xml?channel_id=UCDVYQ4Zhbm3S2dlz7P1GBDg',
      title: 'NFL (YouTube)', category: :youtube_sports,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Official NFL channel — game recaps, highlights, top plays.' },
    { url: 'https://www.youtube.com/feeds/videos.xml?channel_id=UCWJ2lWNubArHWmf3FIHbfcQ',
      title: 'NBA (YouTube)', category: :youtube_sports,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Official NBA channel — game highlights, top plays, dunks.' },
    { url: 'https://www.youtube.com/feeds/videos.xml?channel_id=UCiWLfSweyRNmLpgEHekhoAg',
      title: 'ESPN (YouTube)', category: :youtube_sports,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'ESPN — multi-sport highlights, analysis, breaking news clips.' },
    { url: 'https://www.youtube.com/feeds/videos.xml?channel_id=UCG5qGWdu8nIRZqJ_GgDwQ-w',
      title: 'Premier League (YouTube)', category: :youtube_sports,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Official English Premier League — match highlights, behind-the-scenes.' },
    { url: 'https://www.youtube.com/feeds/videos.xml?channel_id=UCSZbXT5TLLW_i-5W8FZpFsg',
      title: 'Major League Soccer (YouTube)', category: :youtube_sports,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Official MLS channel — Union, every club, match highlights.' },
    { url: 'https://www.youtube.com/feeds/videos.xml?channel_id=UCr2QLMGN6BJ96f_k3Q8f5zQ',
      title: 'UEFA (YouTube)', category: :youtube_sports,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'UEFA — international football, Champions League, Europa, EURO.' },
    { url: 'https://www.youtube.com/feeds/videos.xml?channel_id=UCLcSuj4B8YyUVJdVDeozFQg',
      title: 'UEFA Champions League (YouTube)', category: :youtube_sports,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Champions League official channel — matchday highlights + classics.' },

    # ---- Webcomics & humor (8) ----------------------------------------
    # STUFF #65. All publicly available, free, no paywall, no API key.
    # PERSONAL_BLOG_INTERVAL (4h) since most update daily-ish at most.
    { url: 'https://xkcd.com/atom.xml',
      title: 'xkcd', category: :webcomics,
      interval: FeedsStore::PERSONAL_BLOG_INTERVAL, seed: false,
      blurb: "Randall Munroe's stick-figure science, math, and internet humor — the canonical webcomic." },
    { url: 'https://www.smbc-comics.com/comic/rss',
      title: 'Saturday Morning Breakfast Cereal', category: :webcomics,
      interval: FeedsStore::PERSONAL_BLOG_INTERVAL, seed: false,
      blurb: "Zach Weinersmith's daily strip — science, philosophy, and dark absurdism." },
    { url: 'https://feeds.feedburner.com/oatmealfeed',
      title: 'The Oatmeal', category: :webcomics,
      interval: FeedsStore::PERSONAL_BLOG_INTERVAL, seed: false,
      blurb: "Matthew Inman's internet humor and long-form comic essays." },
    { url: 'https://existentialcomics.com/rss.xml',
      title: 'Existential Comics', category: :webcomics,
      interval: FeedsStore::PERSONAL_BLOG_INTERVAL, seed: false,
      blurb: 'Philosophy in four panels — Kant, Sartre, and friends caught off-guard.' },
    { url: 'https://www.qwantz.com/rssfeed.php',
      title: 'Dinosaur Comics', category: :webcomics,
      interval: FeedsStore::PERSONAL_BLOG_INTERVAL, seed: false,
      blurb: "Ryan North's six-panel dialogue comic — the art never changes." },
    { url: 'https://poorlydrawnlines.com/feed/',
      title: 'Poorly Drawn Lines', category: :webcomics,
      interval: FeedsStore::PERSONAL_BLOG_INTERVAL, seed: false,
      blurb: "Reza Farazmand's quiet, weird, deadpan strips." },
    { url: 'https://wondermark.com/feed/',
      title: 'Wondermark', category: :webcomics,
      interval: FeedsStore::PERSONAL_BLOG_INTERVAL, seed: false,
      blurb: "David Malki's vintage-clipart Victorian-era panel comic." },
    { url: 'https://feeds.feedburner.com/Explosm',
      title: 'Cyanide & Happiness', category: :webcomics,
      interval: FeedsStore::PERSONAL_BLOG_INTERVAL, seed: false,
      blurb: "Explosm.net's absurd stick-figure black-comedy strip." },

    # ---- Finance & Markets (6) ------------------------------------------
    # STUFF #85. Major financial news publishers. PUBLISHER_INTERVAL (1h)
    # since markets move continuously during trading hours.
    { url: 'https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=100003114',
      title: 'CNBC Top News', category: :markets_news,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Breaking business news and market coverage from CNBC.' },
    { url: 'https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=15839069',
      title: 'CNBC Investing', category: :markets_news,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Investment news, portfolio strategy, and stock picks.' },
    { url: 'https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=20910258',
      title: 'CNBC Economy', category: :markets_news,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'US and global economic data, Fed policy, jobs, and inflation.' },
    { url: 'https://feeds.content.dowjones.io/public/rss/mw_topstories',
      title: 'MarketWatch Top Stories', category: :markets_news,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Top market stories from MarketWatch — equities, bonds, commodities.' },
    { url: 'https://seekingalpha.com/feed.xml',
      title: 'Seeking Alpha', category: :markets_news,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Crowd-sourced stock analysis and breaking market news.' },
    { url: 'https://news.google.com/rss/topics/CAAqJggKIiBDQkFTRWdvSUwyMHZNRGx6TVdZU0FtVnVHZ0pWVXlnQVAB',
      title: 'Google News — Business', category: :markets_news,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Aggregated business news from Google — Bloomberg, WSJ, Reuters, and more.' },

    # ---- World News (8) -------------------------------------------------
    # STUFF #85. Major global news outlets with working RSS feeds.
    { url: 'https://www.aljazeera.com/xml/rss/all.xml',
      title: 'Al Jazeera', category: :world,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'International news from Al Jazeera — Middle East, Africa, Asia, and global affairs.' },
    { url: 'https://rss.nytimes.com/services/xml/rss/nyt/World.xml',
      title: 'NYT World News', category: :world,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'New York Times world coverage — conflict, diplomacy, and global trends.' },
    { url: 'https://feeds.washingtonpost.com/rss/world',
      title: 'Washington Post — World', category: :world,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'International reporting from the Washington Post.' },
    { url: 'https://feeds.theguardian.com/theguardian/world/rss',
      title: 'The Guardian — World', category: :world,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Global news and analysis from The Guardian.' },
    { url: 'https://www.cbsnews.com/latest/rss/world',
      title: 'CBS News — World', category: :world,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'World news headlines from CBS News.' },
    { url: 'https://news.un.org/feed/subscribe/en/news/all/rss.xml',
      title: 'UN News', category: :world,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Official United Nations news — humanitarian, climate, peace, and development.' },
    { url: 'https://www.france24.com/en/rss',
      title: 'France 24', category: :world,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'International news from France 24 in English.' },

    # ---- Science (8) ----------------------------------------------------
    # STUFF #85. Top science and space publishers.
    { url: 'https://www.nature.com/nature.rss',
      title: 'Nature', category: :science_pub,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Latest research and news from Nature — the world\'s leading multidisciplinary science journal.' },
    { url: 'https://www.newscientist.com/section/news/feed/',
      title: 'New Scientist', category: :science_pub,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Science and technology news from New Scientist.' },
    { url: 'https://www.sciencedaily.com/rss/all.xml',
      title: 'ScienceDaily', category: :science_pub,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Breaking science research news — biology, chemistry, physics, earth science.' },
    { url: 'https://feeds.arstechnica.com/arstechnica/science',
      title: 'Ars Technica — Science', category: :science_pub,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Ars Technica\'s science desk — peer-reviewed research explained for tech readers.' },
    { url: 'https://www.quantamagazine.org/feed/',
      title: 'Quanta Magazine', category: :science_pub,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'In-depth science and math journalism from the Simons Foundation.' },
    { url: 'https://www.livescience.com/feeds/all',
      title: 'Live Science', category: :science_pub,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Science news, discoveries, and explainers for a general audience.' },
    { url: 'https://www.nasa.gov/news-release/feed/',
      title: 'NASA News', category: :space,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Official NASA press releases — missions, discoveries, and launches.' },
    { url: 'https://www.space.com/feeds/all',
      title: 'Space.com', category: :space,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Space exploration, astronomy, and stargazing news.' },

    # ---- Gaming (8) -----------------------------------------------------
    # STUFF #85. Major gaming news publishers.
    { url: 'https://kotaku.com/rss',
      title: 'Kotaku', category: :gaming_pub,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Gaming news, reviews, and culture from Kotaku.' },
    { url: 'https://feeds.feedburner.com/ign/all',
      title: 'IGN', category: :gaming_pub,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Games, movies, and entertainment news from IGN.' },
    { url: 'https://www.pcgamer.com/rss/',
      title: 'PC Gamer', category: :gaming_pub,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'PC gaming news, hardware, and reviews.' },
    { url: 'https://www.rockpapershotgun.com/feed',
      title: 'Rock Paper Shotgun', category: :gaming_pub,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'PC gaming news and criticism with a sharp editorial voice.' },
    { url: 'https://www.eurogamer.net/feed',
      title: 'Eurogamer', category: :gaming_pub,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'European gaming news and Digital Foundry tech analysis.' },
    { url: 'https://www.polygon.com/rss/index.xml',
      title: 'Polygon', category: :gaming_pub,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Gaming, entertainment, and pop culture from Polygon.' },
    { url: 'https://www.gamespot.com/feeds/mashup/',
      title: 'GameSpot', category: :gaming_pub,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Game reviews, trailers, and news from GameSpot.' },
    { url: 'https://www.destructoid.com/feed/',
      title: 'Destructoid', category: :gaming_pub,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Indie and mainstream gaming news from Destructoid.' },

    # ---- food & cooking (STUFF #88) ---------------------------------------
    # Recipe blogs & cooking
    { url: 'https://feeds.feedburner.com/seriouseats/recipes',
      title: 'Serious Eats', category: :food_recipes,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Rigorously tested recipes and food science from J. Kenji López-Alt and team.' },
    { url: 'https://smittenkitchen.com/feed/',
      title: 'Smitten Kitchen', category: :food_recipes,
      interval: FeedsStore::PERSONAL_BLOG_INTERVAL, seed: false,
      blurb: 'Deb Perelman\'s beloved home-cooking blog — unfussy recipes with real results.' },
    { url: 'https://www.epicurious.com/feed/rss',
      title: 'Epicurious', category: :food_recipes,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Recipes, cooking techniques, and kitchen guides from Condé Nast.' },
    { url: 'https://www.101cookbooks.com/feed',
      title: '101 Cookbooks', category: :food_recipes,
      interval: FeedsStore::PERSONAL_BLOG_INTERVAL, seed: false,
      blurb: 'Heidi Swanson\'s vegetarian and whole-food recipes — beautifully photographed.' },
    # Food journalism
    { url: 'https://www.eater.com/rss/index.xml',
      title: 'Eater', category: :food_news,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Restaurant news, openings, food culture, and where to eat from Vox Media.' },
    { url: 'https://www.bonappetit.com/feed/rss',
      title: 'Bon Appétit', category: :food_news,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Recipes, restaurant guides, and food culture journalism from Condé Nast.' },
    { url: 'https://feeds.npr.org/1057/rss.xml',
      title: 'NPR Food (The Salt)', category: :food_news,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'NPR\'s food desk — the intersection of food, farming, culture, and science.' },
    { url: 'https://civileats.com/feed/',
      title: 'Civil Eats', category: :food_news,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Independent reporting on food systems, agriculture, and food justice.' },
    { url: 'https://www.davidlebovitz.com/feed/',
      title: 'David Lebovitz', category: :food_news,
      interval: FeedsStore::PERSONAL_BLOG_INTERVAL, seed: false,
      blurb: 'Paris-based pastry chef and author — recipes, travel, and French food culture.' },
    # Food podcasts
    { url: 'https://feeds.megaphone.fm/VMP6255701211',
      title: 'Gastropod', category: :food_podcasts,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Cynthia Graber and Nicola Twilley explore food through the lens of science and history.' },
    { url: 'https://feeds.simplecast.com/n91GPFY5',
      title: 'The Sporkful', category: :food_podcasts,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Dan Pashman\'s food podcast — not for foodies, for eaters.' },

    # ---- NPR news topics (5) — STUFF #89 ----------------------------------
    { url: 'https://feeds.npr.org/1001/rss.xml',
      title: 'NPR News', category: :npr_news,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Top stories from NPR\'s national newsroom.' },
    { url: 'https://feeds.npr.org/1014/rss.xml',
      title: 'NPR Politics', category: :npr_news,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Political reporting and analysis from NPR\'s Washington desk.' },
    { url: 'https://feeds.npr.org/1004/rss.xml',
      title: 'NPR World', category: :npr_news,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'International coverage from NPR\'s global correspondents.' },
    { url: 'https://feeds.npr.org/1003/rss.xml',
      title: 'NPR National', category: :npr_news,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Domestic news: communities, policy, and American life.' },
    { url: 'https://feeds.npr.org/1007/rss.xml',
      title: 'NPR Science', category: :npr_news,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Science and environment reporting from NPR.' },

    # ---- NPR podcasts (9) -------------------------------------------------
    { url: 'https://feeds.npr.org/381444908/podcast.xml',
      title: 'Fresh Air', category: :npr_podcasts,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Terry Gross\'s landmark interviews with artists, writers, and thinkers.' },
    { url: 'https://feeds.npr.org/510289/podcast.xml',
      title: 'Planet Money', category: :npr_podcasts,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'The economy explained — with stories and wit.' },
    { url: 'https://feeds.npr.org/510308/podcast.xml',
      title: 'Hidden Brain', category: :npr_podcasts,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Shankar Vedantam on the unconscious patterns that drive human behavior.' },
    { url: 'https://feeds.npr.org/510313/podcast.xml',
      title: 'How I Built This', category: :npr_podcasts,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Guy Raz interviews the founders behind the world\'s most well-known companies.' },
    { url: 'https://feeds.npr.org/344098539/podcast.xml',
      title: "Wait Wait… Don't Tell Me!", category: :npr_podcasts,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'NPR\'s weekly news quiz — funny, irreverent, and surprisingly informative.' },
    { url: 'https://feeds.npr.org/510312/podcast.xml',
      title: 'Code Switch', category: :npr_podcasts,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Race, identity, and culture in America, hosted by journalists of color.' },
    { url: 'https://feeds.npr.org/510351/podcast.xml',
      title: 'Short Wave', category: :npr_podcasts,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Daily science news in under 15 minutes.' },
    { url: 'https://feeds.npr.org/510306/podcast.xml',
      title: 'Tiny Desk Concerts', category: :npr_podcasts,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Bob Boilen\'s legendary office concert series in audio form.' },
    { url: 'https://feeds.npr.org/510310/podcast.xml',
      title: 'NPR Politics Podcast', category: :npr_podcasts,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'NPR\'s politics reporters break down the week\'s news in conversation.' },

    # ---- PBS NewsHour (5) — STUFF #89 -------------------------------------
    { url: 'https://www.pbs.org/newshour/feeds/rss/headlines',
      title: 'PBS NewsHour', category: :pbs_news,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Daily in-depth news from America\'s most-watched evening newscast.' },
    { url: 'https://www.pbs.org/newshour/feeds/rss/politics',
      title: 'PBS NewsHour – Politics', category: :pbs_news,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Political coverage and analysis from PBS NewsHour.' },
    { url: 'https://www.pbs.org/newshour/feeds/rss/world',
      title: 'PBS NewsHour – World', category: :pbs_news,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'International news and foreign policy from PBS NewsHour.' },
    { url: 'https://www.pbs.org/newshour/feeds/rss/science',
      title: 'PBS NewsHour – Science', category: :pbs_news,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Science, health, and technology reporting from PBS NewsHour.' },
    { url: 'https://www.pbs.org/newshour/feeds/rss/health',
      title: 'PBS NewsHour – Health', category: :pbs_news,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Health and medicine reporting from PBS NewsHour.' },

    # ---- PBS shows & documentaries (4) ------------------------------------
    { url: 'https://www.pbs.org/wgbh/nova/rss/nova.xml',
      title: 'NOVA', category: :pbs_shows,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'PBS\'s flagship science documentary series — episodes and previews.' },
    { url: 'https://feeds.feedburner.com/FrontlineAudiocastPbs',
      title: 'Frontline', category: :pbs_shows,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Award-winning investigative journalism from PBS — audio companion track.' },
    { url: 'https://feeds.wgbh.org/322/feed-rss.xml',
      title: 'NOVA Presents', category: :pbs_shows,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Podcast companion to the NOVA documentary series.' },
    { url: 'https://feeds.wgbh.org/3195/feed-rss.xml',
      title: 'American Experience', category: :pbs_shows,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Podcast companion to PBS\'s landmark American history documentary series.' }
  ].freeze

  module_function

  # Every catalog entry, insertion-ordered.
  def all
    CATALOG
  end

  # { :aggregator => [...], :publisher => [...], ... } in CATEGORIES order.
  def by_category
    grouped = CATALOG.group_by { |e| e[:category] }
    CATEGORIES.keys.each_with_object({}) do |cat, h|
      h[cat] = grouped[cat] || []
    end
  end

  # Resolve an entry's top-level topic from its sub-category. The
  # catalog stores `:category` per row; `:topic` is derived from
  # CATEGORY_TO_TOPIC so we don't have to keep both fields in sync
  # by hand on every entry.
  def topic_for(entry_or_category)
    cat = entry_or_category.is_a?(Hash) ? entry_or_category[:category] : entry_or_category
    CATEGORY_TO_TOPIC[cat] || :general
  end

  # { :technology => { :aggregator => [...], ... }, :sports => {...} }
  # — two-level nest used by the catalog browse view to surface a
  # "Technology" / "Sports" outer split with sub-categories inside.
  def by_topic
    grouped = CATALOG.group_by { |e| topic_for(e) }
    TOPICS.keys.each_with_object({}) do |topic, h|
      entries = grouped[topic] || []
      sub = entries.group_by { |e| e[:category] }
      h[topic] = CATEGORIES.keys.each_with_object({}) do |cat, hh|
        rows = sub[cat] || []
        hh[cat] = rows unless rows.empty?
      end
    end
  end

  # Default seed set — the entries flagged `seed: true`. Used by
  # scripts/seed_feeds.rb to populate a fresh install.
  def seed_defaults
    CATALOG.select { |e| e[:seed] }
  end

  # First-time onboarding starter sets per topic chip. Maintained
  # as URL lookups (not category-globs) so we curate the exact mix —
  # rebalancing one topic doesn't have to mean adding/removing
  # `seed: true` flags across CATALOG. URLs that don't resolve in
  # CATALOG (renamed or dropped) are silently skipped so a future
  # drift doesn't 500 the /welcome flow.
  ONBOARDING_STARTERS = {
    technology: %w[
      https://news.ycombinator.com/rss
      https://lobste.rs/rss
      https://www.theverge.com/rss/index.xml
      https://feeds.arstechnica.com/arstechnica/index
      https://simonwillison.net/atom/everything/
      https://blog.cloudflare.com/rss/
    ].freeze,
    sports: %w[
      https://www.bleedinggreennation.com/rss/index.xml
      https://www.libertyballers.com/rss/index.xml
      https://phillysoccerpage.net/feed/
      https://feeds.bbci.co.uk/sport/rugby-union/rss.xml
      https://www.espn.com/espn/rss/tennis/news
    ].freeze,
    nature: %w[
      https://www.youtube.com/feeds/videos.xml?channel_id=UCwmZiChSryoWQCZMIQezgTg
      https://www.youtube.com/feeds/videos.xml?channel_id=UCpVm7bg6pXKo1Pr6k5kxG9A
      https://www.youtube.com/feeds/videos.xml?channel_id=UCkzTTu69cSxxab41OHrBfvQ
      https://www.youtube.com/feeds/videos.xml?channel_id=UCQtW2oz8ec8pHjjxawujNjg
    ].freeze,
    podcasts: %w[
      https://changelog.com/podcast/feed
      https://lexfridman.com/feed/podcast/
      https://feeds.simplecast.com/l2i9YnTd
      https://feeds.simplecast.com/BqbsxVfO
      https://feeds.simplecast.com/Sl5CSM3S
    ].freeze,
    humor: %w[
      https://xkcd.com/atom.xml
      https://www.smbc-comics.com/comic/rss
      https://feeds.feedburner.com/oatmealfeed
      https://existentialcomics.com/rss.xml
      https://www.qwantz.com/rssfeed.php
      https://poorlydrawnlines.com/feed/
    ].freeze,
    finance: %w[
      https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=100003114
      https://feeds.content.dowjones.io/public/rss/mw_topstories
      https://seekingalpha.com/feed.xml
    ].freeze,
    world_news: %w[
      https://www.aljazeera.com/xml/rss/all.xml
      https://rss.nytimes.com/services/xml/rss/nyt/World.xml
    ].freeze,
    science: %w[
      https://www.nature.com/nature.rss
      https://www.nasa.gov/news-release/feed/
      https://www.quantamagazine.org/feed/
    ].freeze,
    gaming: %w[
      https://kotaku.com/rss
      https://www.pcgamer.com/rss/
      https://www.polygon.com/rss/index.xml
    ].freeze,
    food: %w[
      https://www.eater.com/rss/index.xml
      https://feeds.feedburner.com/seriouseats/recipes
      https://smittenkitchen.com/feed/
      https://www.bonappetit.com/feed/rss
      https://feeds.megaphone.fm/VMP6255701211
      https://feeds.simplecast.com/n91GPFY5
    ].freeze,
    npr: %w[
      https://feeds.npr.org/1001/rss.xml
      https://feeds.npr.org/381444908/podcast.xml
      https://feeds.npr.org/510289/podcast.xml
      https://feeds.npr.org/510308/podcast.xml
    ].freeze,
    pbs: %w[
      https://www.pbs.org/newshour/feeds/rss/headlines
      https://www.pbs.org/wgbh/nova/rss/nova.xml
      https://feeds.feedburner.com/FrontlineAudiocastPbs
      https://feeds.wgbh.org/3195/feed-rss.xml
    ].freeze
  }.freeze

  # Onboarding-chip labels. Surfaces in views/welcome.erb so the
  # label + the catalog-driven feed list are pulled from the same
  # place — adding a chip is a CATALOG-only change.
  ONBOARDING_CHIPS = {
    technology: { label: 'Technology',  blurb: 'Tech news + engineering blogs + AI commentary.', emoji: '💻' },
    sports:     { label: 'Sports',      blurb: 'NFL / NBA / soccer / rugby / tennis news.',       emoji: '🏟' },
    nature:     { label: 'Nature',      blurb: 'BBC Earth, Nat Geo, PBS Nature documentaries.',   emoji: '📺' },
    podcasts:   { label: 'Podcasts',    blurb: 'Long-form audio: Changelog, Lex Fridman, more.',  emoji: '🎧' },
    humor:      { label: 'Humor',       blurb: 'xkcd, SMBC, The Oatmeal, and friends — daily-ish webcomics.', emoji: '😂' },
    finance:    { label: 'Finance',    blurb: 'CNBC, MarketWatch, Seeking Alpha — market headlines.',        emoji: '📈' },
    world_news: { label: 'World News', blurb: 'NPR, NYT, Al Jazeera, The Guardian — global coverage.',      emoji: '🌍' },
    science:    { label: 'Science',    blurb: 'Nature, NASA, Quanta Magazine — research & discovery.',       emoji: '🔬' },
    gaming:     { label: 'Gaming',     blurb: 'Kotaku, IGN, PC Gamer, Polygon — game news & reviews.',      emoji: '🎮' },
    food:       { label: 'Food & Cooking', blurb: 'Serious Eats, Eater, Bon Appétit + food podcasts.', emoji: '🍳' },
    npr:        { label: 'NPR',            blurb: 'Fresh Air, Planet Money, news, politics + more.', emoji: '📻' },
    pbs:        { label: 'PBS',            blurb: 'NewsHour, NOVA, Frontline, American Experience.',  emoji: '🎬' }
  }.freeze

  def starters_for_topic(topic)
    urls = ONBOARDING_STARTERS[topic.to_sym] || []
    urls.filter_map { |url| find_by_url(url) }
  end

  def find_by_url(url)
    CATALOG.find { |e| e[:url] == url }
  end

  # Phase 4 (2026-05-12). Score unsubscribed catalog entries by their
  # similarity to what the user has already subscribed to, return the
  # top N. Algorithm:
  #
  #   • For every subscribed feed that's in the catalog, accumulate
  #     weights: +2 for its category, +1 for its topic.
  #   • Score each unsubscribed catalog entry by summing the weights
  #     of its (category, topic).
  #   • Return entries with score > 0, descending — discards entries
  #     whose category isn't represented by any subscription.
  #
  # Returns [] cold-start (no overlap with the catalog at all). Used
  # by the /feeds view to put a "Recommended for you" callout above
  # the full catalog browse, which got intimidating at 79 entries.
  def recommend_for(subscribed_urls:, limit: 6)
    subscribed = Array(subscribed_urls).to_set
    cat_weight, topic_weight = Hash.new(0), Hash.new(0)
    subscribed.each do |url|
      entry = find_by_url(url)
      next unless entry
      cat_weight[entry[:category]] += 1
      topic_weight[topic_for(entry)] += 1
    end
    return [] if cat_weight.empty?

    CATALOG.reject { |e| subscribed.include?(e[:url]) }
           .map { |e| [e, cat_weight[e[:category]] * 2 + topic_weight[topic_for(e)]] }
           .select { |(_, s)| s.positive? }
           .sort_by { |(_, s)| -s }
           .first(limit)
           .map(&:first)
  end

  # STUFF #52 PR3 — bridge from SportsCatalog league slugs to a curated
  # list of FeedCatalog URLs. Lets /sports/manage/:sport/:league render
  # a "News + podcasts" subscribe panel without polluting either
  # catalog with cross-references. Many leagues share feeds (BBC
  # Cricket covers ICC + WPL + IPL + The Hundred), so this is a
  # many-to-many: each league lists every URL that meaningfully
  # covers it.
  SPORTS_LEAGUE_FEEDS = {
    # Football
    'nfl' => %w[
      https://www.bleedinggreennation.com/rss/index.xml
      https://www.espn.com/espn/rss/nfl/news
      https://feeds.megaphone.fm/VMP9406149033
    ],
    # Basketball
    'nba' => %w[
      https://www.libertyballers.com/rss/index.xml
      https://www.espn.com/espn/rss/nba/news
      https://feeds.simplecast.com/jxr32ewl
    ],
    'wnba' => %w[
      https://www.espn.com/espn/rss/wnba/news
    ],
    'euroleague' => %w[
      https://feeds.bbci.co.uk/sport/football/european/rss.xml
    ],
    # Soccer
    'mls' => %w[
      https://phillysoccerpage.net/feed/
      https://www.espn.com/espn/rss/soccer/news
      https://phillysoccerpage.net/category/podcasts/all-three-points/feed/
    ],
    'nwsl' => %w[
      https://feeds.bbci.co.uk/sport/football/womens/rss.xml
      https://www.espn.com/espn/rss/soccer/news
    ],
    'epl' => %w[
      https://feeds.bbci.co.uk/sport/football/premier-league/rss.xml
      https://www.espn.com/espn/rss/soccer/news
    ],
    'wsl' => %w[
      https://feeds.bbci.co.uk/sport/football/womens/rss.xml
    ],
    'la-liga' => %w[
      https://feeds.bbci.co.uk/sport/football/european/rss.xml
      https://www.espn.com/espn/rss/soccer/news
    ],
    'liga-mx' => %w[
      https://www.espn.com/espn/rss/soccer/news
    ],
    'bundesliga' => %w[
      https://feeds.bbci.co.uk/sport/football/european/rss.xml
    ],
    'bundesliga-frauen' => %w[
      https://feeds.bbci.co.uk/sport/football/womens/rss.xml
    ],
    'serie-a' => %w[
      https://feeds.bbci.co.uk/sport/football/european/rss.xml
    ],
    'serie-a-femminile' => %w[
      https://feeds.bbci.co.uk/sport/football/womens/rss.xml
    ],
    'saudi-pro-league' => %w[
      https://www.espn.com/espn/rss/soccer/news
    ],
    'brasileirao' => %w[
      https://www.espn.com/espn/rss/soccer/news
    ],
    'j-league' => %w[
      https://www.espn.com/espn/rss/soccer/news
    ],
    'wel-league' => %w[
      https://feeds.bbci.co.uk/sport/football/womens/rss.xml
    ],
    'egyptian-premier' => %w[
      https://feeds.bbci.co.uk/sport/football/african/rss.xml
    ],
    'caf-afcon' => %w[
      https://feeds.bbci.co.uk/sport/football/african/rss.xml
    ],
    'caf-wafcon' => %w[
      https://feeds.bbci.co.uk/sport/football/african/rss.xml
      https://feeds.bbci.co.uk/sport/football/womens/rss.xml
    ],
    'copa-libertadores' => %w[
      https://www.espn.com/espn/rss/soccer/news
    ],
    'afc-asian-cup' => %w[
      https://www.espn.com/espn/rss/soccer/news
    ],
    'fifa-world' => %w[
      https://www.espn.com/espn/rss/soccer/news
      https://feeds.bbci.co.uk/sport/football/european/rss.xml
    ],
    'fifa-womens-world' => %w[
      https://feeds.bbci.co.uk/sport/football/womens/rss.xml
    ],
    # Rugby
    'rugby-championship' => %w[
      https://feeds.bbci.co.uk/sport/rugby-union/rss.xml
      https://www.rnz.co.nz/rss/sport.xml
      https://feeds.acast.com/public/shows/aotearoa-rugby-pod
      https://feeds.megaphone.fm/GLT9898976502
    ],
    'six-nations' => %w[
      https://feeds.bbci.co.uk/sport/rugby-union/rss.xml
    ],
    'womens-rugby-world' => %w[
      https://feeds.bbci.co.uk/sport/rugby-union/rss.xml
      https://www.rnz.co.nz/rss/sport.xml
    ],
    # Tennis
    'atp' => %w[
      https://www.espn.com/espn/rss/tennis/news
      https://feeds.bbci.co.uk/sport/tennis/rss.xml
      https://tennis365.com/feed
      https://feeds.acast.com/public/shows/thetennispodcast
    ],
    'wta' => %w[
      https://www.espn.com/espn/rss/tennis/news
      https://feeds.bbci.co.uk/sport/tennis/rss.xml
      https://tennis365.com/feed
      https://feeds.acast.com/public/shows/thetennispodcast
    ],
    # Baseball
    'mlb' => %w[
      https://www.espn.com/espn/rss/mlb/news
      https://feeds.bbci.co.uk/sport/baseball/rss.xml
    ],
    # STUFF #52.3 — NPB has no dedicated English RSS feed I can
    # find. Closest reliable proxies: BBC Sport Baseball (worldwide
    # baseball, regular NPB mentions especially around Japan Series)
    # and ESPN MLB (heavy coverage of Japanese players in MLB —
    # Ohtani, Yamamoto, Suzuki). Both stable; users get a baseline.
    'npb' => %w[
      https://feeds.bbci.co.uk/sport/baseball/rss.xml
      https://www.espn.com/espn/rss/mlb/news
    ],
    # KBO has a dedicated independent English site (MyKBO) — primary
    # source. Yonhap News covers Korean sports broadly including KBO.
    'kbo' => %w[
      https://mykbo.net/feed/
      https://en.yna.co.kr/RSS/sports.xml
      https://feeds.bbci.co.uk/sport/baseball/rss.xml
    ],
    # Cricket
    'icc-mens' => %w[
      https://feeds.bbci.co.uk/sport/cricket/rss.xml
      https://www.espn.com/espn/rss/cricinfo/news
    ],
    'icc-womens' => %w[
      https://feeds.bbci.co.uk/sport/cricket/rss.xml
      https://www.espn.com/espn/rss/cricinfo/news
    ],
    'ipl' => %w[
      https://feeds.bbci.co.uk/sport/cricket/rss.xml
      https://www.espn.com/espn/rss/cricinfo/news
    ],
    'wpl' => %w[
      https://feeds.bbci.co.uk/sport/cricket/rss.xml
      https://www.espn.com/espn/rss/cricinfo/news
    ],
    'bbl' => %w[
      https://feeds.bbci.co.uk/sport/cricket/rss.xml
      https://www.espn.com/espn/rss/cricinfo/news
    ],
    'wbbl' => %w[
      https://feeds.bbci.co.uk/sport/cricket/rss.xml
      https://www.espn.com/espn/rss/cricinfo/news
    ],
    'the-hundred-men' => %w[
      https://feeds.bbci.co.uk/sport/cricket/rss.xml
    ],
    'the-hundred-women' => %w[
      https://feeds.bbci.co.uk/sport/cricket/rss.xml
    ],
    # Golf
    'pga-tour' => %w[
      https://www.espn.com/espn/rss/golf/news
      https://feeds.bbci.co.uk/sport/golf/rss.xml
    ],
    'lpga' => %w[
      https://www.espn.com/espn/rss/golf/news
      https://feeds.bbci.co.uk/sport/golf/rss.xml
    ],
    'dp-world-tour' => %w[
      https://www.espn.com/espn/rss/golf/news
      https://feeds.bbci.co.uk/sport/golf/rss.xml
    ],
    'ladies-european' => %w[
      https://feeds.bbci.co.uk/sport/golf/rss.xml
    ],
    'liv-golf' => %w[
      https://www.espn.com/espn/rss/golf/news
    ],
    # Motorsport
    'formula-1' => %w[
      https://feeds.bbci.co.uk/sport/formula1/rss.xml
      https://www.espn.com/espn/rss/rpm/news
    ],
    'f1-academy' => %w[
      https://feeds.bbci.co.uk/sport/formula1/rss.xml
    ],
    'nascar-cup' => %w[
      https://www.espn.com/espn/rss/rpm/news
    ],
    'indycar' => %w[
      https://www.espn.com/espn/rss/rpm/news
    ],
    'wec' => %w[
      https://www.espn.com/espn/rss/rpm/news
    ],
    # Badminton — BWF (Badminton World Federation) publishes an
    # official news feed; Badzine is the established independent
    # English-language badminton news outlet. Both cover men's +
    # women's singles + doubles across all tours, so bound to both
    # league entries. STUFF #52.3.
    'bwf-mens' => %w[
      https://bwfbadminton.com/news/feed/
      https://www.badzine.net/feed/
    ],
    'bwf-womens' => %w[
      https://bwfbadminton.com/news/feed/
      https://www.badzine.net/feed/
    ],
    # Horse racing
    'uk-flat'         => %w[https://feeds.bbci.co.uk/sport/horse-racing/rss.xml],
    'uk-jumps'        => %w[https://feeds.bbci.co.uk/sport/horse-racing/rss.xml],
    'us-triple-crown' => %w[https://feeds.bbci.co.uk/sport/horse-racing/rss.xml],
    'dubai-world-cup' => %w[https://feeds.bbci.co.uk/sport/horse-racing/rss.xml]
  }.freeze

  # Return the catalog entries (full hash with title + blurb + category)
  # that cover this sports league. Empty array when no URLs are
  # bound or the bound URL doesn't exist in CATALOG.
  def feeds_for_sports_league(league_slug)
    urls = SPORTS_LEAGUE_FEEDS[league_slug.to_s] || []
    urls.map { |u| find_by_url(u) }.compact
  end
end
