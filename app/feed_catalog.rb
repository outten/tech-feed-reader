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
  CATEGORIES = {
    aggregator:  'Aggregators',
    publisher:   'Tech publishers',
    engineering: 'Engineering blogs',
    ai:          'AI / ML',
    security:    'Security',
    personal:    'Personal blogs',
    podcast:     'Podcasts'
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

    # ---- security (3) -------------------------------------------------
    { url: 'https://krebsonsecurity.com/feed/', title: 'Krebs on Security', category: :security,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Investigative reporting on cybercrime and breaches.' },
    { url: 'https://www.schneier.com/feed/atom/', title: 'Schneier on Security', category: :security,
      interval: FeedsStore::PERSONAL_BLOG_INTERVAL, seed: false,
      blurb: 'Bruce Schneier on security, privacy, and policy.' },
    { url: 'https://www.bleepingcomputer.com/feed/', title: 'Bleeping Computer', category: :security,
      interval: FeedsStore::PUBLISHER_INTERVAL, seed: false,
      blurb: 'Daily breach disclosures and malware analysis.' },

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
      blurb: 'Long-running Star Trek fan audio drama — full-cast adventures aboard the USS Excelsior.' }
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

  # Default seed set — the entries flagged `seed: true`. Used by
  # scripts/seed_feeds.rb to populate a fresh install.
  def seed_defaults
    CATALOG.select { |e| e[:seed] }
  end

  def find_by_url(url)
    CATALOG.find { |e| e[:url] == url }
  end
end
