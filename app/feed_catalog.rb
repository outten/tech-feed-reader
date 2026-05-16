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
    nature:     'Nature & Documentary'
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
    # Sports (Phase S2)
    nfl:         'NFL',
    nba:         'NBA',
    soccer:      'Soccer (MLS / international)',
    rugby:       'Rugby',
    tennis:      'Tennis',
    # STUFF.md #16 — nature / documentary YouTube channels
    youtube_nature: 'Nature & wildlife (YouTube)',
    # Phase 2 follow-up (2026-05-12) — sports YouTube channels so
    # game highlights / league channels surface in /whats-on's "To
    # watch today" alongside nature.
    youtube_sports: 'Sports (YouTube)',
    # STUFF.md #18 — mythology / classical history (Greek / Roman / Norse).
    mythos:      'Mythology & classical history'
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
    nfl:         :sports,
    nba:         :sports,
    soccer:      :sports,
    rugby:       :sports,
    tennis:      :sports,
    youtube_nature: :nature,
    youtube_sports: :sports,
    mythos:      :technology
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
      blurb: 'Champions League official channel — matchday highlights + classics.' }
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
    ].freeze
  }.freeze

  # Onboarding-chip labels. Surfaces in views/welcome.erb so the
  # label + the catalog-driven feed list are pulled from the same
  # place — adding a chip is a CATALOG-only change.
  ONBOARDING_CHIPS = {
    technology: { label: 'Technology',  blurb: 'Tech news + engineering blogs + AI commentary.', emoji: '💻' },
    sports:     { label: 'Sports',      blurb: 'NFL / NBA / soccer / rugby / tennis news.',       emoji: '🏟' },
    nature:     { label: 'Nature',      blurb: 'BBC Earth, Nat Geo, PBS Nature documentaries.',   emoji: '📺' },
    podcasts:   { label: 'Podcasts',    blurb: 'Long-form audio: Changelog, Lex Fridman, more.',  emoji: '🎧' }
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
end
