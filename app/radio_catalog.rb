module RadioCatalog
  # All stream URLs verified live as of 2026-06-03.
  # Image URLs verified 2026-06-08. Note: Radio Swiss image paths are _nuxt build
  # artifacts — stable until the site redeploys with a changed logo.
  # catalog: groups stations by provider for display on /radio.

  STATIONS = [
    # ── SomaFM ─────────────────────────────────────────────────────────────
    {
      name:        'Groove Salad',
      description: 'A nicely chilled plate of ambient/downtempo beats and grooves.',
      genre:       'Ambient / Downtempo',
      stream_url:  'https://ice1.somafm.com/groovesalad-256-mp3',
      image_url:   'https://somafm.com/img3/groovesalad-400.jpg',
      home_url:    'https://somafm.com/groovesalad/',
      catalog:     'SomaFM'
    },
    {
      name:        'Drone Zone',
      description: 'Served up to you straight from the zone: droning, dark, ambient techno.',
      genre:       'Dark Ambient',
      stream_url:  'https://ice1.somafm.com/dronezone-256-mp3',
      image_url:   'https://somafm.com/img3/dronezone-400.jpg',
      home_url:    'https://somafm.com/dronezone/',
      catalog:     'SomaFM'
    },
    {
      name:        'Secret Agent',
      description: 'The soundtrack for your stylish, mysterious, dangerous life.',
      genre:       'Lounge / Spy',
      stream_url:  'https://ice1.somafm.com/secretagent-128-mp3',
      image_url:   'https://somafm.com/img3/secretagent-400.jpg',
      home_url:    'https://somafm.com/secretagent/',
      catalog:     'SomaFM'
    },
    {
      name:        'Space Station Soma',
      description: 'Tune in, turn on, space out. Spaced-out ambient and mid-tempo electronica.',
      genre:       'Space / Electronic',
      stream_url:  'https://ice1.somafm.com/spacestation-128-mp3',
      image_url:   'https://somafm.com/img3/spacestation-400.jpg',
      home_url:    'https://somafm.com/spacestation/',
      catalog:     'SomaFM'
    },
    {
      name:        'Indie Pop Rocks',
      description: 'New and classic indiepop tracks.',
      genre:       'Indie Pop',
      stream_url:  'https://ice1.somafm.com/indiepop-128-mp3',
      image_url:   'https://somafm.com/img3/indiepop-400.jpg',
      home_url:    'https://somafm.com/indiepop/',
      catalog:     'SomaFM'
    },
    {
      name:        'DEF CON Radio',
      description: 'Music for Hacking. The official DEF CON stream.',
      genre:       'Electronic / Hacker',
      stream_url:  'https://ice1.somafm.com/defcon-128-mp3',
      image_url:   'https://somafm.com/img3/defcon-400.jpg',
      home_url:    'https://somafm.com/defcon/',
      catalog:     'SomaFM'
    },
    {
      name:        'Underground 80s',
      description: 'Early 80s UK underground, campus and alternative radio hits.',
      genre:       '80s / New Wave',
      stream_url:  'https://ice1.somafm.com/u80s-256-mp3',
      image_url:   'https://somafm.com/img3/u80s-400.jpg',
      home_url:    'https://somafm.com/u80s/',
      catalog:     'SomaFM'
    },
    {
      name:        'Lush',
      description: 'Sensuous and mellow vocals, mostly female, with an electronic influence.',
      genre:       'Dream Pop',
      stream_url:  'https://ice1.somafm.com/lush-128-mp3',
      image_url:   'https://somafm.com/img3/lush-400.jpg',
      home_url:    'https://somafm.com/lush/',
      catalog:     'SomaFM'
    },
    {
      name:        'Fluid',
      description: 'Drown in the flow of wet electronics.',
      genre:       'Nu-Jazz / IDM',
      stream_url:  'https://ice1.somafm.com/fluid-128-mp3',
      image_url:   'https://somafm.com/img3/fluid-400.jpg',
      home_url:    'https://somafm.com/fluid/',
      catalog:     'SomaFM'
    },
    {
      name:        'Cliqhop IDM',
      description: 'Blips, clicks and cuts. Downtempo, IDM, glitch and more.',
      genre:       'IDM / Glitch',
      stream_url:  'https://ice1.somafm.com/cliqhop-128-mp3',
      image_url:   'https://somafm.com/img3/cliqhop-400.jpg',
      home_url:    'https://somafm.com/cliqhop/',
      catalog:     'SomaFM'
    },

    # ── KCRW ───────────────────────────────────────────────────────────────
    {
      name:        'KCRW',
      description: 'Santa Monica\'s eclectic public radio — music, news, and culture. Home of Morning Becomes Eclectic.',
      genre:       'Eclectic / Public Radio',
      stream_url:  'https://kcrw.streamguys1.com/kcrw_192k_mp3_on_air',
      image_url:   'https://www.kcrw.com/static/images/kcrw-logo-share.jpg',
      home_url:    'https://www.kcrw.com/music',
      catalog:     'Public Radio'
    },

    # ── KEXP ───────────────────────────────────────────────────────────────
    {
      name:        'KEXP',
      description: 'Seattle\'s independent public radio. Where the music matters.',
      genre:       'Indie / Alternative',
      stream_url:  'https://kexp-mp3-128.streamguys1.com/kexp128.mp3',
      image_url:   'https://www.kexp.org/static/assets/img/logo-header.svg',
      home_url:    'https://www.kexp.org',
      catalog:     'Public Radio'
    },

    # ── WFMU ───────────────────────────────────────────────────────────────
    {
      name:        'WFMU',
      description: 'Freeform radio. Listener-supported, non-commercial. A cult favourite in tech circles.',
      genre:       'Freeform',
      stream_url:  'https://stream0.wfmu.org/freeform-128k.mp3',
      image_url:   'https://www.wfmu.org/images/wfmu-logo.svg',
      home_url:    'https://wfmu.org',
      catalog:     'Public Radio'
    },

    # ── Radio Paradise ─────────────────────────────────────────────────────
    {
      name:        'Radio Paradise — Main Mix',
      description: 'Eclectic, commercial-free. Blends rock, world, electronic, and more. Listener-supported.',
      genre:       'Eclectic / Rock',
      stream_url:  'https://stream.radioparadise.com/mp3-192',
      image_url:   'https://www.radioparadise.com/graphics/rp_logo-1500.png',
      home_url:    'https://radioparadise.com',
      catalog:     'Independent'
    },
    {
      name:        'Radio Paradise — Mellow Mix',
      description: 'The laid-back side of Radio Paradise.',
      genre:       'Mellow / Chill',
      stream_url:  'https://stream.radioparadise.com/mellow-192',
      image_url:   'https://www.radioparadise.com/graphics/rp_logo-1500.png',
      home_url:    'https://radioparadise.com/player',
      catalog:     'Independent'
    },

    # ── NTS Radio ──────────────────────────────────────────────────────────
    {
      name:        'NTS Radio 1',
      description: 'London-based independent radio. Eclectic programming from broadcasters worldwide.',
      genre:       'Eclectic / Independent',
      stream_url:  'https://stream-relay-geo.ntslive.net/stream',
      image_url:   'https://www.nts.live/img/nts-logo.svg',
      home_url:    'https://www.nts.live',
      catalog:     'Independent'
    },
    {
      name:        'NTS Radio 2',
      description: "NTS's second channel — deeper cuts, rarer music, experimental and underground.",
      genre:       'Experimental / Underground',
      stream_url:  'https://stream-relay-geo.ntslive.net/stream2',
      image_url:   'https://www.nts.live/img/nts-logo.svg',
      home_url:    'https://www.nts.live/2',
      catalog:     'Independent'
    },
    {
      name:        'TSF Jazz',
      description: "Paris's beloved all-jazz station. The soundtrack to every Parisian café and code session.",
      genre:       'Jazz',
      stream_url:  'https://tsfjazz.ice.infomaniak.ch/tsfjazz-high.mp3',
      image_url:   'https://www.tsfjazz.com/themes/custom/tsfjazz/images/tsfjazz-l-256.png',
      home_url:    'https://www.tsfjazz.com',
      catalog:     'Independent'
    },

    # ── FIP / Radio France ─────────────────────────────────────────────────
    # THE "music to code by" family. No ads, no DJ chatter, just music.
    # France's public broadcaster runs a family of genre channels off the
    # same icecast infrastructure — all verified 2026-06-03.
    {
      name:        'FIP',
      description: "France's premier \"music to code by\" station. Eclectic, ad-free, zero chatter — an extraordinary mix of jazz, rock, world, classical and electronic. Beloved in tech circles worldwide.",
      genre:       'Eclectic / Coding',
      stream_url:  'https://icecast.radiofrance.fr/fip-midfi.mp3',
      image_url:   'https://www.radiofrance.fr/pikapi/images/a8903fd7-01e2-45a1-b768-61e3d8e1ff6a/1200x680',
      home_url:    'https://www.radiofrance.fr/fip',
      catalog:     'FIP / Radio France'
    },
    {
      name:        'FIP Jazz',
      description: "FIP's dedicated jazz channel. From bebop to neo-soul — no ads, no filler.",
      genre:       'Jazz',
      stream_url:  'https://icecast.radiofrance.fr/fipjazz-midfi.mp3',
      image_url:   'https://www.radiofrance.fr/pikapi/images/a8903fd7-01e2-45a1-b768-61e3d8e1ff6a/1200x680',
      home_url:    'https://www.radiofrance.fr/fip/fip-autour-du-jazz',
      catalog:     'FIP / Radio France'
    },
    {
      name:        'FIP Rock',
      description: "FIP's rock channel — indie, alternative and classics, curated and commercial-free.",
      genre:       'Rock / Indie',
      stream_url:  'https://icecast.radiofrance.fr/fiprock-midfi.mp3',
      image_url:   'https://www.radiofrance.fr/pikapi/images/a8903fd7-01e2-45a1-b768-61e3d8e1ff6a/1200x680',
      home_url:    'https://www.radiofrance.fr/fip/fip-rock',
      catalog:     'FIP / Radio France'
    },
    {
      name:        'FIP Electro',
      description: 'Electronic, house and techno curated the French way — sophisticated and diverse.',
      genre:       'Electronic / House',
      stream_url:  'https://icecast.radiofrance.fr/fipelectro-midfi.mp3',
      image_url:   'https://www.radiofrance.fr/pikapi/images/a8903fd7-01e2-45a1-b768-61e3d8e1ff6a/1200x680',
      home_url:    'https://www.radiofrance.fr/fip/fip-electro',
      catalog:     'FIP / Radio France'
    },
    {
      name:        'FIP World',
      description: 'Global sounds from every continent — afrobeat, bossa nova, reggae, and beyond.',
      genre:       'World Music',
      stream_url:  'https://icecast.radiofrance.fr/fipworld-midfi.mp3',
      image_url:   'https://www.radiofrance.fr/pikapi/images/a8903fd7-01e2-45a1-b768-61e3d8e1ff6a/1200x680',
      home_url:    'https://www.radiofrance.fr/fip/fip-monde',
      catalog:     'FIP / Radio France'
    },
    {
      name:        'FIP Reggae',
      description: 'Roots, dancehall, dub and lovers rock — the full reggae spectrum, commercial-free.',
      genre:       'Reggae / Dub',
      stream_url:  'https://icecast.radiofrance.fr/fipreggae-midfi.mp3',
      image_url:   'https://www.radiofrance.fr/pikapi/images/a8903fd7-01e2-45a1-b768-61e3d8e1ff6a/1200x680',
      home_url:    'https://www.radiofrance.fr/fip/fip-reggae',
      catalog:     'FIP / Radio France'
    },
    {
      name:        'France Musique',
      description: "Radio France's classical and jazz station. Concerts, operas, and in-depth music programming.",
      genre:       'Classical / Jazz',
      stream_url:  'https://icecast.radiofrance.fr/francemusique-midfi.mp3',
      image_url:   'https://www.radiofrance.fr/pikapi/images/33f46583-7f6f-4d09-8ac3-29415de896cb/1200x680',
      home_url:    'https://www.radiofrance.fr/francemusique',
      catalog:     'FIP / Radio France'
    },

    # ── Swiss Radio (SRG SSR) ──────────────────────────────────────────────
    # Switzerland's public broadcaster runs three genre stations popular
    # worldwide for focused, ad-free listening. Streams respond 405 to HEAD
    # (icecast quirk) but deliver audio normally on GET.
    {
      name:        'Radio Swiss Jazz',
      description: "Switzerland's all-jazz public radio. Relaxed, sophisticated, consistently great for focused work.",
      genre:       'Jazz',
      stream_url:  'https://stream.srg-ssr.ch/m/rsj/mp3_128',
      image_url:   'https://www.radioswissjazz.ch/_nuxt/img/rsj-logo-50-x2.c637176.png',
      home_url:    'https://www.radioswissjazz.ch',
      catalog:     'Swiss Radio'
    },
    {
      name:        'Radio Swiss Classic',
      description: 'Ad-free classical music 24/7 from the Swiss Broadcasting Corporation. Ideal for deep-focus sessions.',
      genre:       'Classical',
      stream_url:  'https://stream.srg-ssr.ch/m/rsc_de/mp3_128',
      image_url:   'https://www.radioswissclassic.ch/_nuxt/img/rsc-logo-50-x2.63a9918.png',
      home_url:    'https://www.radioswissclassic.ch',
      catalog:     'Swiss Radio'
    },
    {
      name:        'Radio Swiss Pop',
      description: 'Eclectic, thoughtful pop from Switzerland — no charts-only playlists, no ads.',
      genre:       'Pop / Eclectic',
      stream_url:  'https://stream.srg-ssr.ch/m/rsp/mp3_128',
      image_url:   'https://www.radioswisspop.ch/_nuxt/img/rsp-logo-50-x2.6ec92b0.png',
      home_url:    'https://www.radioswisspop.ch',
      catalog:     'Swiss Radio'
    },

    # ── Public Radio (additional) ──────────────────────────────────────────
    {
      name:        'The Current',
      description: "Minnesota Public Radio's music station. New, indie and alternative — one of the most respected in the US and beloved in tech communities.",
      genre:       'Indie / Alternative',
      stream_url:  'https://current.stream.publicradio.org/kcmp.mp3',
      image_url:   'https://www.thecurrent.org/images/the-current-default-social-image.png',
      home_url:    'https://www.thecurrent.org',
      catalog:     'Public Radio'
    },
    {
      name:        'WXPN — Philadelphia',
      description: "University of Pennsylvania's legendary AAA station. Adventurous, listener-supported, central to Philly's music scene.",
      genre:       'AAA / Indie',
      stream_url:  'https://wxpn.xpn.org/xpnmp3hi',
      image_url:   'https://backend.xpn.org/app/uploads/2022/04/wxpn_home_featured.jpg',
      home_url:    'https://xpn.org',
      catalog:     'Public Radio'
    },
    {
      name:        'WNYC FM 93.9 — New York',
      description: 'New York Public Radio. News, culture, and music from the world\'s media capital.',
      genre:       'Public Radio / News',
      stream_url:  'https://fm939.wnyc.org/wnycfm.mp3',
      image_url:   'https://media.wnyc.org/i/1200/630/c/80/1/wnyc_square_logo.png',
      home_url:    'https://www.wnyc.org',
      catalog:     'Public Radio'
    },
    {
      name:        'Triple J — Australia',
      description: "Australia's national youth broadcaster. Indie, alternative, and new music — the launching pad for countless global artists.",
      genre:       'Indie / Alternative',
      stream_url:  'https://live-radio01.mediahubaustralia.com/2TJW/mp3/',
      image_url:   'https://www.abc.net.au/core-assets/triplej/abc-triplej.png?imformat=generic',
      home_url:    'https://www.abc.net.au/triplej',
      catalog:     'Public Radio'
    }
  ].freeze

  # All unique catalog group names in display order.
  GROUPS = STATIONS.map { |s| s[:catalog] }.uniq.freeze

  def self.by_group
    STATIONS.group_by { |s| s[:catalog] }
  end

  def self.find_by_stream_url(url)
    STATIONS.find { |s| s[:stream_url] == url }
  end
end
