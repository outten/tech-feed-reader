# STUFF #52 — hand-curated sports catalog. Source of truth for what
# /sports/manage exposes as browseable + followable.
#
# Why static Ruby (vs DB table): edits land in PRs with diffs you can
# read, no migrations to roll, no admin UI to build. The /sports/manage
# UI reads this catalog directly; follow actions upsert the league +
# team into sports_leagues + sports_teams on demand so the live-scores
# pipeline (ESPN scoreboard / standings / team-schedule) keeps working
# off the same DB rows it already used.
#
# Equal-weight policy: every sport that has a women's pro counterpart
# lists it alongside the men's league, in the same drill-down. Where
# no women's pro league exists today (NFL, F1 proper), we say so
# rather than omitting silently.
#
# Global representation: soccer carries leagues for Africa (CAF),
# South America (CONMEBOL), and Asia (AFC) in addition to the US +
# European entries.
#
# Provider integration: leagues that have a working ESPN sport_path
# carry `source_provider: 'espn'` + `external_id: '<sport>/<league>'`.
# Those leagues get live scores + standings via Providers::ESPN.
# Leagues without it are still browseable + followable, just without
# live data (RSS feeds carry the news in PR 3 of #52).
module SportsCatalog
  module_function

  # Top-level: sport-slug → metadata + leagues. Slugs are URL-safe
  # lowercase-with-dashes. The order here is the display order on the
  # /sports/manage landing page.
  SPORTS = {
    'football' => {
      name: 'American Football',
      emoji: '🏈',
      region: 'us',
      blurb: 'NFL on Sundays. No major women\'s pro league today (WFA is amateur).',
      leagues: [
        {
          slug: 'nfl', name: 'NFL', sport: 'football', women: false,
          region: 'us', country: 'US',
          source_provider: 'espn', external_id: 'football/nfl',
          teams: [
            { slug: 'eagles',  name: 'Philadelphia Eagles', short_name: 'Eagles',
              location: 'Philadelphia',
              source_provider: 'espn', external_id: '21' },
            { slug: 'cowboys', name: 'Dallas Cowboys',      short_name: 'Cowboys',
              location: 'Dallas',
              source_provider: 'espn', external_id: '6' },
            { slug: 'chiefs',  name: 'Kansas City Chiefs',  short_name: 'Chiefs',
              location: 'Kansas City',
              source_provider: 'espn', external_id: '12' },
            { slug: 'niners',  name: 'San Francisco 49ers', short_name: '49ers',
              location: 'San Francisco',
              source_provider: 'espn', external_id: '25' },
            { slug: 'bills',   name: 'Buffalo Bills',       short_name: 'Bills',
              location: 'Buffalo',
              source_provider: 'espn', external_id: '2' }
          ]
        }
      ]
    },

    'basketball' => {
      name: 'Basketball',
      emoji: '🏀',
      region: 'global',
      blurb: 'NBA + WNBA at equal weight. EuroLeague for the European game.',
      leagues: [
        {
          slug: 'nba', name: 'NBA', sport: 'basketball', women: false,
          region: 'us', country: 'US',
          source_provider: 'espn', external_id: 'basketball/nba',
          teams: [
            { slug: 'sixers',  name: 'Philadelphia 76ers',     short_name: 'Sixers',
              location: 'Philadelphia',
              source_provider: 'espn', external_id: '20' },
            { slug: 'celtics', name: 'Boston Celtics',         short_name: 'Celtics',
              location: 'Boston',
              source_provider: 'espn', external_id: '2' },
            { slug: 'lakers',  name: 'Los Angeles Lakers',     short_name: 'Lakers',
              location: 'Los Angeles',
              source_provider: 'espn', external_id: '13' },
            { slug: 'warriors', name: 'Golden State Warriors', short_name: 'Warriors',
              location: 'Golden State',
              source_provider: 'espn', external_id: '9' },
            { slug: 'bucks',   name: 'Milwaukee Bucks',        short_name: 'Bucks',
              location: 'Milwaukee',
              source_provider: 'espn', external_id: '15' }
          ]
        },
        {
          slug: 'wnba', name: 'WNBA', sport: 'basketball', women: true,
          region: 'us', country: 'US',
          source_provider: 'espn', external_id: 'basketball/wnba',
          teams: [
            { slug: 'wnba-aces',    name: 'Las Vegas Aces',       short_name: 'Aces',
              location: 'Las Vegas',     source_provider: 'espn', external_id: '17' },
            { slug: 'wnba-liberty', name: 'New York Liberty',     short_name: 'Liberty',
              location: 'New York',      source_provider: 'espn', external_id: '9' },
            { slug: 'wnba-fever',   name: 'Indiana Fever',        short_name: 'Fever',
              location: 'Indiana',       source_provider: 'espn', external_id: '5' },
            { slug: 'wnba-lynx',    name: 'Minnesota Lynx',       short_name: 'Lynx',
              location: 'Minnesota',     source_provider: 'espn', external_id: '8' },
            { slug: 'wnba-sun',     name: 'Connecticut Sun',      short_name: 'Sun',
              location: 'Connecticut',   source_provider: 'espn', external_id: '18' }
          ]
        },
        {
          slug: 'euroleague', name: 'EuroLeague', sport: 'basketball', women: false,
          region: 'europe', country: nil,
          teams: [
            { slug: 'real-madrid-bc', name: 'Real Madrid Baloncesto', short_name: 'Real Madrid',
              location: 'Madrid' },
            { slug: 'fcb-bc',         name: 'FC Barcelona Bàsquet',   short_name: 'Barça',
              location: 'Barcelona' },
            { slug: 'panathinaikos-bc', name: 'Panathinaikos',        short_name: 'Panathinaikos',
              location: 'Athens' },
            { slug: 'olympiacos-bc',  name: 'Olympiacos',             short_name: 'Olympiacos',
              location: 'Piraeus' }
          ]
        }
      ]
    },

    'soccer' => {
      name: 'Soccer',
      emoji: '⚽',
      region: 'global',
      blurb: 'Every continent represented. Women\'s WSL + NWSL alongside Premier League + MLS.',
      leagues: [
        {
          slug: 'mls', name: 'Major League Soccer', sport: 'soccer', women: false,
          region: 'us', country: 'US',
          source_provider: 'espn', external_id: 'soccer/usa.1',
          teams: [
            { slug: 'union',    name: 'Philadelphia Union', short_name: 'Union',
              location: 'Philadelphia',
              source_provider: 'espn', external_id: '10739' },
            { slug: 'lafc',     name: 'Los Angeles FC',     short_name: 'LAFC',
              location: 'Los Angeles' },
            { slug: 'inter-miami', name: 'Inter Miami CF',  short_name: 'Inter Miami',
              location: 'Miami' },
            { slug: 'seattle-sounders', name: 'Seattle Sounders FC', short_name: 'Sounders',
              location: 'Seattle' }
          ]
        },
        {
          slug: 'nwsl', name: 'NWSL', sport: 'soccer', women: true,
          region: 'us', country: 'US',
          teams: [
            { slug: 'nwsl-thorns',   name: 'Portland Thorns FC',  short_name: 'Thorns',
              location: 'Portland' },
            { slug: 'nwsl-current',  name: 'Kansas City Current', short_name: 'Current',
              location: 'Kansas City' },
            { slug: 'nwsl-gotham',   name: 'NJ/NY Gotham FC',     short_name: 'Gotham',
              location: 'New Jersey' },
            { slug: 'nwsl-orlando',  name: 'Orlando Pride',       short_name: 'Pride',
              location: 'Orlando' }
          ]
        },
        {
          slug: 'epl', name: 'Premier League', sport: 'soccer', women: false,
          region: 'europe', country: 'GB',
          source_provider: 'espn', external_id: 'soccer/eng.1',
          teams: [
            { slug: 'arsenal',     name: 'Arsenal FC',         short_name: 'Arsenal',
              location: 'London' },
            { slug: 'man-city',    name: 'Manchester City',    short_name: 'Man City',
              location: 'Manchester' },
            { slug: 'liverpool',   name: 'Liverpool FC',       short_name: 'Liverpool',
              location: 'Liverpool' },
            { slug: 'chelsea',     name: 'Chelsea FC',         short_name: 'Chelsea',
              location: 'London' },
            { slug: 'tottenham',   name: 'Tottenham Hotspur',  short_name: 'Spurs',
              location: 'London' }
          ]
        },
        {
          slug: 'wsl', name: "Women's Super League", sport: 'soccer', women: true,
          region: 'europe', country: 'GB',
          teams: [
            { slug: 'wsl-chelsea',  name: 'Chelsea FC Women',   short_name: 'Chelsea',
              location: 'London' },
            { slug: 'wsl-arsenal',  name: 'Arsenal Women',      short_name: 'Arsenal',
              location: 'London' },
            { slug: 'wsl-man-city', name: 'Manchester City Women', short_name: 'Man City',
              location: 'Manchester' },
            { slug: 'wsl-man-utd',  name: 'Manchester United Women', short_name: 'Man United',
              location: 'Manchester' }
          ]
        },
        {
          slug: 'la-liga', name: 'La Liga', sport: 'soccer', women: false,
          region: 'europe', country: 'ES',
          source_provider: 'espn', external_id: 'soccer/esp.1',
          teams: [
            { slug: 'real-madrid', name: 'Real Madrid',     short_name: 'Real Madrid',
              location: 'Madrid' },
            { slug: 'barcelona',   name: 'FC Barcelona',    short_name: 'Barça',
              location: 'Barcelona' },
            { slug: 'atletico',    name: 'Atlético Madrid', short_name: 'Atlético',
              location: 'Madrid' }
          ]
        },
        {
          slug: 'liga-mx', name: 'Liga MX', sport: 'soccer', women: false,
          region: 'north-america', country: 'MX',
          source_provider: 'espn', external_id: 'soccer/mex.1',
          teams: [
            { slug: 'club-america', name: 'Club América',    short_name: 'América',
              location: 'Mexico City' },
            { slug: 'chivas',       name: 'Guadalajara',     short_name: 'Chivas',
              location: 'Guadalajara' },
            { slug: 'cruz-azul',    name: 'Cruz Azul',       short_name: 'Cruz Azul',
              location: 'Mexico City' }
          ]
        },
        {
          slug: 'bundesliga', name: 'Bundesliga', sport: 'soccer', women: false,
          region: 'europe', country: 'DE',
          source_provider: 'espn', external_id: 'soccer/ger.1',
          blurb: 'Germany\'s top men\'s tier.',
          teams: [
            { slug: 'bayern',         name: 'Bayern Munich',        short_name: 'Bayern',
              location: 'Munich' },
            { slug: 'dortmund',       name: 'Borussia Dortmund',    short_name: 'Dortmund',
              location: 'Dortmund' },
            { slug: 'leverkusen',     name: 'Bayer 04 Leverkusen',  short_name: 'Leverkusen',
              location: 'Leverkusen' },
            { slug: 'rb-leipzig',     name: 'RB Leipzig',           short_name: 'RB Leipzig',
              location: 'Leipzig' }
          ]
        },
        {
          slug: 'bundesliga-frauen', name: 'Frauen-Bundesliga', sport: 'soccer', women: true,
          region: 'europe', country: 'DE',
          blurb: 'Germany\'s top women\'s league.',
          teams: [
            { slug: 'bundesliga-w-bayern', name: 'Bayern Munich (W)',
              short_name: 'Bayern', location: 'Munich' },
            { slug: 'bundesliga-w-wolfsburg', name: 'VfL Wolfsburg (W)',
              short_name: 'Wolfsburg', location: 'Wolfsburg' },
            { slug: 'bundesliga-w-frankfurt', name: 'Eintracht Frankfurt (W)',
              short_name: 'Frankfurt', location: 'Frankfurt' }
          ]
        },
        {
          slug: 'serie-a', name: 'Serie A', sport: 'soccer', women: false,
          region: 'europe', country: 'IT',
          source_provider: 'espn', external_id: 'soccer/ita.1',
          blurb: 'Italy\'s top men\'s tier.',
          teams: [
            { slug: 'inter-milan',    name: 'Inter Milan',          short_name: 'Inter',
              location: 'Milan' },
            { slug: 'ac-milan',       name: 'AC Milan',             short_name: 'Milan',
              location: 'Milan' },
            { slug: 'juventus',       name: 'Juventus',             short_name: 'Juventus',
              location: 'Turin' },
            { slug: 'napoli',         name: 'Napoli',               short_name: 'Napoli',
              location: 'Naples' },
            { slug: 'as-roma',        name: 'AS Roma',              short_name: 'Roma',
              location: 'Rome' }
          ]
        },
        {
          slug: 'serie-a-femminile', name: 'Serie A Femminile', sport: 'soccer', women: true,
          region: 'europe', country: 'IT',
          blurb: 'Italy\'s top women\'s tier.',
          teams: [
            { slug: 'serie-a-w-roma', name: 'AS Roma (W)',         short_name: 'Roma',
              location: 'Rome' },
            { slug: 'serie-a-w-juve', name: 'Juventus (W)',        short_name: 'Juventus',
              location: 'Turin' },
            { slug: 'serie-a-w-fiorentina', name: 'Fiorentina (W)', short_name: 'Fiorentina',
              location: 'Florence' }
          ]
        },
        {
          slug: 'saudi-pro-league', name: 'Saudi Pro League', sport: 'soccer', women: false,
          region: 'middle-east', country: 'SA',
          blurb: 'Saudi Arabia\'s top flight; rapid global signings since 2023.',
          teams: [
            { slug: 'al-nassr',       name: 'Al-Nassr',             short_name: 'Al-Nassr',
              location: 'Riyadh' },
            { slug: 'al-hilal',       name: 'Al-Hilal',             short_name: 'Al-Hilal',
              location: 'Riyadh' },
            { slug: 'al-ittihad',     name: 'Al-Ittihad',           short_name: 'Al-Ittihad',
              location: 'Jeddah' },
            { slug: 'al-ahli-jeddah', name: 'Al-Ahli',              short_name: 'Al-Ahli',
              location: 'Jeddah' }
          ]
        },
        {
          slug: 'brasileirao', name: 'Brasileirão Série A', sport: 'soccer', women: false,
          region: 'south-america', country: 'BR',
          source_provider: 'espn', external_id: 'soccer/bra.1',
          blurb: 'Brazil\'s top men\'s tier.',
          teams: [
            { slug: 'brasileirao-flamengo', name: 'CR Flamengo',         short_name: 'Flamengo',
              location: 'Rio de Janeiro' },
            { slug: 'brasileirao-palmeiras', name: 'Palmeiras',           short_name: 'Palmeiras',
              location: 'São Paulo' },
            { slug: 'brasileirao-corinthians', name: 'Corinthians',       short_name: 'Corinthians',
              location: 'São Paulo' },
            { slug: 'brasileirao-sao-paulo', name: 'São Paulo FC',        short_name: 'São Paulo',
              location: 'São Paulo' },
            { slug: 'brasileirao-fluminense', name: 'Fluminense',         short_name: 'Fluminense',
              location: 'Rio de Janeiro' }
          ]
        },
        {
          slug: 'j-league', name: 'J1 League', sport: 'soccer', women: false,
          region: 'asia', country: 'JP',
          blurb: 'Japan\'s top men\'s tier.',
          teams: [
            { slug: 'j-league-marinos', name: 'Yokohama F. Marinos', short_name: 'F. Marinos',
              location: 'Yokohama' },
            { slug: 'j-league-frontale', name: 'Kawasaki Frontale',   short_name: 'Frontale',
              location: 'Kawasaki' },
            { slug: 'j-league-vissel',  name: 'Vissel Kobe',          short_name: 'Vissel',
              location: 'Kobe' },
            { slug: 'j-league-urawa',   name: 'Urawa Red Diamonds',   short_name: 'Reds',
              location: 'Saitama' }
          ]
        },
        {
          slug: 'wel-league', name: 'WE League', sport: 'soccer', women: true,
          region: 'asia', country: 'JP',
          blurb: 'Japan\'s first fully professional women\'s league (launched 2021).',
          teams: [
            { slug: 'we-league-inac', name: 'INAC Kobe Leonessa',       short_name: 'INAC Kobe',
              location: 'Kobe' },
            { slug: 'we-league-urawa', name: 'Mitsubishi Heavy Industries Urawa Reds Ladies',
              short_name: 'Urawa Reds Ladies', location: 'Saitama' },
            { slug: 'we-league-tokyo-verdy', name: 'Nippon TV Tokyo Verdy Beleza',
              short_name: 'Tokyo Verdy Beleza', location: 'Tokyo' }
          ]
        },
        {
          slug: 'egyptian-premier', name: 'Egyptian Premier League', sport: 'soccer', women: false,
          region: 'africa', country: 'EG',
          blurb: 'Egypt\'s top tier; the Cairo derby is one of Africa\'s biggest matches.',
          teams: [
            { slug: 'al-ahly',         name: 'Al Ahly SC',          short_name: 'Al Ahly',
              location: 'Cairo' },
            { slug: 'zamalek',         name: 'Zamalek SC',          short_name: 'Zamalek',
              location: 'Cairo' },
            { slug: 'pyramids',        name: 'Pyramids FC',         short_name: 'Pyramids',
              location: 'Cairo' }
          ]
        },
        {
          slug: 'caf-afcon', name: 'Africa Cup of Nations', sport: 'soccer', women: false,
          region: 'africa', country: nil,
          blurb: 'CAF Africa Cup of Nations — biennial men\'s national-team championship.',
          teams: [
            { slug: 'afcon-nigeria', name: 'Nigeria',  short_name: 'Nigeria',  location: 'Nigeria' },
            { slug: 'afcon-egypt',   name: 'Egypt',    short_name: 'Egypt',    location: 'Egypt' },
            { slug: 'afcon-senegal', name: 'Senegal',  short_name: 'Senegal',  location: 'Senegal' },
            { slug: 'afcon-morocco', name: 'Morocco',  short_name: 'Morocco',  location: 'Morocco' },
            { slug: 'afcon-cote-divoire', name: "Côte d'Ivoire", short_name: 'Ivory Coast',
              location: "Côte d'Ivoire" }
          ]
        },
        {
          slug: 'caf-wafcon', name: "Women's Africa Cup of Nations", sport: 'soccer', women: true,
          region: 'africa', country: nil,
          blurb: 'CAF Women\'s Africa Cup of Nations — continental women\'s championship.',
          teams: [
            { slug: 'wafcon-nigeria', name: 'Nigeria',  short_name: 'Nigeria',  location: 'Nigeria' },
            { slug: 'wafcon-south-africa', name: 'South Africa', short_name: 'South Africa',
              location: 'South Africa' },
            { slug: 'wafcon-morocco',  name: 'Morocco', short_name: 'Morocco',  location: 'Morocco' }
          ]
        },
        {
          slug: 'copa-libertadores', name: 'Copa Libertadores', sport: 'soccer', women: false,
          region: 'south-america', country: nil,
          blurb: 'CONMEBOL Libertadores — South America\'s top club championship.',
          teams: [
            { slug: 'flamengo',   name: 'Flamengo',          short_name: 'Flamengo',
              location: 'Rio de Janeiro' },
            { slug: 'palmeiras',  name: 'Palmeiras',         short_name: 'Palmeiras',
              location: 'São Paulo' },
            { slug: 'boca',       name: 'Boca Juniors',      short_name: 'Boca',
              location: 'Buenos Aires' },
            { slug: 'river-plate', name: 'River Plate',      short_name: 'River',
              location: 'Buenos Aires' }
          ]
        },
        {
          slug: 'afc-asian-cup', name: 'AFC Asian Cup', sport: 'soccer', women: false,
          region: 'asia', country: nil,
          blurb: 'AFC Asian Cup — Asia\'s flagship men\'s national-team tournament.',
          teams: [
            { slug: 'afc-japan',       name: 'Japan',       short_name: 'Japan',       location: 'Japan' },
            { slug: 'afc-south-korea', name: 'South Korea', short_name: 'South Korea', location: 'South Korea' },
            { slug: 'afc-saudi',       name: 'Saudi Arabia', short_name: 'Saudi Arabia',
              location: 'Saudi Arabia' },
            { slug: 'afc-iran',        name: 'Iran',         short_name: 'Iran',        location: 'Iran' },
            { slug: 'afc-australia',   name: 'Australia',    short_name: 'Australia',   location: 'Australia' }
          ]
        },
        {
          slug: 'fifa-world', name: 'FIFA World Cup', sport: 'soccer', women: false,
          region: 'global', country: nil,
          source_provider: 'espn', external_id: 'soccer/fifa.world',
          blurb: 'Men\'s World Cup — every four years.',
          teams: []  # No persistent team list; participants vary each cycle
        },
        {
          slug: 'fifa-womens-world', name: "FIFA Women's World Cup", sport: 'soccer', women: true,
          region: 'global', country: nil,
          blurb: 'Women\'s World Cup — every four years.',
          teams: []
        }
      ]
    },

    'rugby' => {
      name: 'Rugby',
      emoji: '🏉',
      region: 'global',
      blurb: 'Southern + Northern hemisphere internationals, women\'s + men\'s.',
      leagues: [
        {
          slug: 'rugby-championship', name: 'The Rugby Championship', sport: 'rugby', women: false,
          region: 'southern-hemisphere', country: nil,
          source_provider: 'espn', external_id: 'rugby/244293',
          teams: [
            { slug: 'all-blacks',  name: 'New Zealand', short_name: 'All Blacks',
              location: 'New Zealand',
              source_provider: 'espn', external_id: '8' },
            { slug: 'wallabies',   name: 'Australia',   short_name: 'Wallabies',
              location: 'Australia' },
            { slug: 'springboks',  name: 'South Africa', short_name: 'Springboks',
              location: 'South Africa' },
            { slug: 'pumas',       name: 'Argentina',    short_name: 'Pumas',
              location: 'Argentina' }
          ]
        },
        {
          slug: 'six-nations', name: 'Six Nations', sport: 'rugby', women: false,
          region: 'europe', country: nil,
          teams: [
            { slug: 'ireland-rugby',  name: 'Ireland',  short_name: 'Ireland',  location: 'Ireland' },
            { slug: 'england-rugby',  name: 'England',  short_name: 'England',  location: 'England' },
            { slug: 'france-rugby',   name: 'France',   short_name: 'France',   location: 'France' },
            { slug: 'scotland-rugby', name: 'Scotland', short_name: 'Scotland', location: 'Scotland' },
            { slug: 'wales-rugby',    name: 'Wales',    short_name: 'Wales',    location: 'Wales' },
            { slug: 'italy-rugby',    name: 'Italy',    short_name: 'Italy',    location: 'Italy' }
          ]
        },
        {
          slug: 'womens-rugby-world', name: "Women's Rugby World Cup", sport: 'rugby', women: true,
          region: 'global', country: nil,
          blurb: 'Every four years; growing fast.',
          teams: [
            { slug: 'black-ferns',    name: 'New Zealand', short_name: 'Black Ferns',
              location: 'New Zealand' },
            { slug: 'red-roses',      name: 'England',     short_name: 'Red Roses',
              location: 'England' },
            { slug: 'wrugby-france',  name: 'France',      short_name: 'France',
              location: 'France' },
            { slug: 'wrugby-canada',  name: 'Canada',      short_name: 'Canada',
              location: 'Canada' }
          ]
        }
      ]
    },

    'tennis' => {
      name: 'Tennis',
      emoji: '🎾',
      region: 'global',
      blurb: 'ATP + WTA equal-weight; majors covered through each tour.',
      leagues: [
        {
          slug: 'atp', name: 'ATP Tour', sport: 'tennis', women: false,
          region: 'global', country: nil,
          source_provider: 'espn', external_id: 'tennis/atp',
          blurb: "Men's professional tour.",
          teams: [
            { slug: 'tennis-sinner',   name: 'Jannik Sinner',   short_name: 'Sinner',
              location: 'Italy' },
            { slug: 'tennis-alcaraz',  name: 'Carlos Alcaraz',  short_name: 'Alcaraz',
              location: 'Spain' },
            { slug: 'tennis-djokovic', name: 'Novak Djokovic',  short_name: 'Djokovic',
              location: 'Serbia' },
            { slug: 'tennis-medvedev', name: 'Daniil Medvedev', short_name: 'Medvedev',
              location: 'Russia' }
          ]
        },
        {
          slug: 'wta', name: 'WTA Tour', sport: 'tennis', women: true,
          region: 'global', country: nil,
          source_provider: 'espn', external_id: 'tennis/wta',
          blurb: "Women's professional tour.",
          teams: [
            { slug: 'tennis-swiatek', name: 'Iga Świątek',  short_name: 'Świątek',
              location: 'Poland' },
            { slug: 'tennis-sabalenka', name: 'Aryna Sabalenka', short_name: 'Sabalenka',
              location: 'Belarus' },
            { slug: 'tennis-gauff',   name: 'Coco Gauff',    short_name: 'Gauff',
              location: 'USA' },
            { slug: 'tennis-rybakina', name: 'Elena Rybakina', short_name: 'Rybakina',
              location: 'Kazakhstan' }
          ]
        }
      ]
    },

    'baseball' => {
      name: 'Baseball',
      emoji: '⚾',
      region: 'global',
      blurb: 'MLB + NPB Japan + KBO Korea. (No major women\'s pro baseball league globally today.)',
      leagues: [
        {
          slug: 'mlb', name: 'Major League Baseball', sport: 'baseball', women: false,
          region: 'us', country: 'US',
          source_provider: 'espn', external_id: 'baseball/mlb',
          teams: [
            { slug: 'phillies', name: 'Philadelphia Phillies', short_name: 'Phillies',
              location: 'Philadelphia' },
            { slug: 'yankees',  name: 'New York Yankees',      short_name: 'Yankees',
              location: 'New York' },
            { slug: 'dodgers',  name: 'Los Angeles Dodgers',   short_name: 'Dodgers',
              location: 'Los Angeles' },
            { slug: 'red-sox',  name: 'Boston Red Sox',        short_name: 'Red Sox',
              location: 'Boston' },
            { slug: 'mets',     name: 'New York Mets',         short_name: 'Mets',
              location: 'New York' }
          ]
        },
        {
          slug: 'npb', name: 'Nippon Professional Baseball', sport: 'baseball', women: false,
          region: 'asia', country: 'JP',
          blurb: "Japan's top professional league.",
          teams: [
            { slug: 'npb-giants',  name: 'Yomiuri Giants',         short_name: 'Giants',
              location: 'Tokyo' },
            { slug: 'npb-tigers',  name: 'Hanshin Tigers',         short_name: 'Tigers',
              location: 'Osaka' },
            { slug: 'npb-hawks',   name: 'Fukuoka SoftBank Hawks', short_name: 'Hawks',
              location: 'Fukuoka' },
            { slug: 'npb-eagles',  name: 'Tohoku Rakuten Golden Eagles', short_name: 'Eagles',
              location: 'Sendai' }
          ]
        },
        {
          slug: 'kbo', name: 'Korea Baseball Organization', sport: 'baseball', women: false,
          region: 'asia', country: 'KR',
          blurb: "South Korea's top professional league.",
          teams: [
            { slug: 'kbo-doosan',  name: 'Doosan Bears',     short_name: 'Bears',
              location: 'Seoul' },
            { slug: 'kbo-kt',      name: 'KT Wiz',           short_name: 'KT Wiz',
              location: 'Suwon' },
            { slug: 'kbo-lg',      name: 'LG Twins',         short_name: 'Twins',
              location: 'Seoul' }
          ]
        }
      ]
    },

    'motorsport' => {
      name: 'Motorsport',
      emoji: '🏎️',
      region: 'global',
      blurb: 'F1 + F1 Academy + NASCAR + IndyCar + endurance.',
      leagues: [
        {
          slug: 'formula-1', name: 'Formula 1', sport: 'motorsport', women: false,
          region: 'global', country: nil,
          blurb: "World's top open-wheel racing championship.",
          teams: [
            { slug: 'f1-mercedes',  name: 'Mercedes-AMG Petronas', short_name: 'Mercedes',
              location: 'Brackley, UK' },
            { slug: 'f1-redbull',   name: 'Oracle Red Bull Racing', short_name: 'Red Bull',
              location: 'Milton Keynes, UK' },
            { slug: 'f1-ferrari',   name: 'Scuderia Ferrari',      short_name: 'Ferrari',
              location: 'Maranello, IT' },
            { slug: 'f1-mclaren',   name: 'McLaren F1 Team',       short_name: 'McLaren',
              location: 'Woking, UK' },
            { slug: 'f1-aston-martin', name: 'Aston Martin Aramco F1', short_name: 'Aston Martin',
              location: 'Silverstone, UK' },
            { slug: 'f1-williams',  name: 'Williams Racing',       short_name: 'Williams',
              location: 'Grove, UK' }
          ]
        },
        {
          slug: 'f1-academy', name: 'F1 Academy', sport: 'motorsport', women: true,
          region: 'global', country: nil,
          blurb: 'Women-only single-seater championship feeding the F1 pyramid.',
          teams: []  # F1 Academy is driver-focused, not team-focused
        },
        {
          slug: 'nascar-cup', name: 'NASCAR Cup Series', sport: 'motorsport', women: false,
          region: 'us', country: 'US',
          blurb: "Top tier of US stock-car racing.",
          teams: [
            { slug: 'nascar-hendrick',     name: 'Hendrick Motorsports',
              short_name: 'Hendrick',         location: 'Concord, NC' },
            { slug: 'nascar-joe-gibbs',    name: 'Joe Gibbs Racing',
              short_name: 'JGR',              location: 'Huntersville, NC' },
            { slug: 'nascar-penske',       name: 'Team Penske',
              short_name: 'Penske',           location: 'Mooresville, NC' },
            { slug: 'nascar-stewart-haas', name: 'Stewart-Haas Racing',
              short_name: 'SHR',              location: 'Kannapolis, NC' }
          ]
        },
        {
          slug: 'indycar', name: 'IndyCar Series', sport: 'motorsport', women: false,
          region: 'us', country: 'US',
          blurb: "US open-wheel; the Indianapolis 500 is the season highlight.",
          teams: [
            { slug: 'indy-penske',          name: 'Team Penske',
              short_name: 'Penske',           location: 'Mooresville, NC' },
            { slug: 'indy-ganassi',         name: 'Chip Ganassi Racing',
              short_name: 'Ganassi',          location: 'Indianapolis, IN' },
            { slug: 'indy-andretti',        name: 'Andretti Global',
              short_name: 'Andretti',         location: 'Indianapolis, IN' },
            { slug: 'indy-arrow-mclaren',   name: 'Arrow McLaren',
              short_name: 'Arrow McLaren',    location: 'Indianapolis, IN' }
          ]
        },
        {
          slug: 'wec', name: 'FIA World Endurance Championship', sport: 'motorsport', women: false,
          region: 'global', country: nil,
          blurb: "Sportscar endurance racing; Le Mans 24 is the crown jewel.",
          teams: [
            { slug: 'wec-toyota',   name: 'Toyota Gazoo Racing', short_name: 'Toyota',
              location: 'Cologne, DE' },
            { slug: 'wec-ferrari',  name: 'Ferrari AF Corse',    short_name: 'Ferrari',
              location: 'Maranello, IT' },
            { slug: 'wec-porsche',  name: 'Porsche Penske Motorsport', short_name: 'Porsche',
              location: 'Stuttgart, DE' },
            { slug: 'wec-cadillac', name: 'Cadillac Hertz Team Jota', short_name: 'Cadillac',
              location: 'Detroit, US / Huntingdon, UK' }
          ]
        }
      ]
    },

    'cricket' => {
      name: 'Cricket',
      emoji: '🏏',
      region: 'global',
      blurb: 'Global. Test, ODI, T20. Women\'s competitions equal-weight from the top.',
      leagues: [
        {
          slug: 'icc-mens', name: "ICC Men's Cricket", sport: 'cricket', women: false,
          region: 'global', country: nil,
          blurb: 'International men\'s cricket: World Cups, Test Championships, T20 Internationals.',
          teams: [
            { slug: 'cricket-india',     name: 'India',     short_name: 'India',     location: 'India' },
            { slug: 'cricket-australia', name: 'Australia', short_name: 'Australia', location: 'Australia' },
            { slug: 'cricket-england',   name: 'England',   short_name: 'England',   location: 'England' },
            { slug: 'cricket-pakistan',  name: 'Pakistan',  short_name: 'Pakistan',  location: 'Pakistan' },
            { slug: 'cricket-south-africa', name: 'South Africa', short_name: 'South Africa',
              location: 'South Africa' },
            { slug: 'cricket-new-zealand', name: 'New Zealand', short_name: 'New Zealand',
              location: 'New Zealand' },
            { slug: 'cricket-west-indies', name: 'West Indies', short_name: 'West Indies',
              location: 'Caribbean' }
          ]
        },
        {
          slug: 'icc-womens', name: "ICC Women's Cricket", sport: 'cricket', women: true,
          region: 'global', country: nil,
          blurb: 'International women\'s cricket — Women\'s World Cup, T20 World Cup.',
          teams: [
            { slug: 'wcricket-australia', name: 'Australia', short_name: 'Australia',
              location: 'Australia' },
            { slug: 'wcricket-england',   name: 'England',   short_name: 'England',
              location: 'England' },
            { slug: 'wcricket-india',     name: 'India',     short_name: 'India',
              location: 'India' },
            { slug: 'wcricket-south-africa', name: 'South Africa', short_name: 'South Africa',
              location: 'South Africa' },
            { slug: 'wcricket-new-zealand', name: 'New Zealand', short_name: 'New Zealand',
              location: 'New Zealand' }
          ]
        },
        {
          slug: 'ipl', name: 'Indian Premier League', sport: 'cricket', women: false,
          region: 'asia', country: 'IN',
          blurb: 'Premier men\'s T20 franchise league.',
          teams: [
            { slug: 'ipl-mumbai',     name: 'Mumbai Indians',        short_name: 'Mumbai',
              location: 'Mumbai' },
            { slug: 'ipl-chennai',    name: 'Chennai Super Kings',   short_name: 'Chennai',
              location: 'Chennai' },
            { slug: 'ipl-kolkata',    name: 'Kolkata Knight Riders', short_name: 'Kolkata',
              location: 'Kolkata' },
            { slug: 'ipl-rcb',        name: 'Royal Challengers Bengaluru', short_name: 'RCB',
              location: 'Bengaluru' },
            { slug: 'ipl-delhi',      name: 'Delhi Capitals',        short_name: 'Delhi',
              location: 'Delhi' },
            { slug: 'ipl-rajasthan',  name: 'Rajasthan Royals',      short_name: 'Rajasthan',
              location: 'Jaipur' }
          ]
        },
        {
          slug: 'wpl', name: "Women's Premier League", sport: 'cricket', women: true,
          region: 'asia', country: 'IN',
          blurb: 'India\'s women\'s T20 franchise league.',
          teams: [
            { slug: 'wpl-mumbai',     name: 'Mumbai Indians (W)',       short_name: 'Mumbai',
              location: 'Mumbai' },
            { slug: 'wpl-delhi',      name: 'Delhi Capitals (W)',       short_name: 'Delhi',
              location: 'Delhi' },
            { slug: 'wpl-rcb',        name: 'Royal Challengers Bengaluru (W)', short_name: 'RCB',
              location: 'Bengaluru' },
            { slug: 'wpl-up',         name: 'UP Warriorz',              short_name: 'UP Warriorz',
              location: 'Uttar Pradesh' },
            { slug: 'wpl-gujarat',    name: 'Gujarat Giants (W)',       short_name: 'Gujarat',
              location: 'Gujarat' }
          ]
        },
        {
          slug: 'bbl', name: 'Big Bash League', sport: 'cricket', women: false,
          region: 'oceania', country: 'AU',
          blurb: 'Australian men\'s T20 league.',
          teams: [
            { slug: 'bbl-sixers',    name: 'Sydney Sixers',       short_name: 'Sixers',
              location: 'Sydney' },
            { slug: 'bbl-thunder',   name: 'Sydney Thunder',      short_name: 'Thunder',
              location: 'Sydney' },
            { slug: 'bbl-stars',     name: 'Melbourne Stars',     short_name: 'Stars',
              location: 'Melbourne' },
            { slug: 'bbl-renegades', name: 'Melbourne Renegades', short_name: 'Renegades',
              location: 'Melbourne' },
            { slug: 'bbl-perth',     name: 'Perth Scorchers',     short_name: 'Scorchers',
              location: 'Perth' }
          ]
        },
        {
          slug: 'wbbl', name: "Women's Big Bash League", sport: 'cricket', women: true,
          region: 'oceania', country: 'AU',
          blurb: 'Australia\'s women\'s T20 league.',
          teams: [
            { slug: 'wbbl-sixers',    name: 'Sydney Sixers (W)',    short_name: 'Sixers',
              location: 'Sydney' },
            { slug: 'wbbl-thunder',   name: 'Sydney Thunder (W)',   short_name: 'Thunder',
              location: 'Sydney' },
            { slug: 'wbbl-stars',     name: 'Melbourne Stars (W)',  short_name: 'Stars',
              location: 'Melbourne' },
            { slug: 'wbbl-perth',     name: 'Perth Scorchers (W)',  short_name: 'Scorchers',
              location: 'Perth' }
          ]
        },
        {
          slug: 'the-hundred-men', name: 'The Hundred (Men\'s)', sport: 'cricket', women: false,
          region: 'europe', country: 'GB',
          blurb: '100-ball short-format league in England + Wales.',
          teams: [
            { slug: 'hundred-trent', name: 'Trent Rockets',        short_name: 'Trent Rockets',
              location: 'Nottingham' },
            { slug: 'hundred-oval',  name: 'Oval Invincibles',     short_name: 'Oval',
              location: 'London' },
            { slug: 'hundred-spirit', name: 'London Spirit',       short_name: 'Spirit',
              location: 'London' },
            { slug: 'hundred-superchargers', name: 'Northern Superchargers',
              short_name: 'Superchargers', location: 'Leeds' }
          ]
        },
        {
          slug: 'the-hundred-women', name: 'The Hundred (Women\'s)', sport: 'cricket', women: true,
          region: 'europe', country: 'GB',
          blurb: 'The women\'s side of England\'s 100-ball league.',
          teams: [
            { slug: 'hundred-w-oval', name: 'Oval Invincibles (W)', short_name: 'Oval',
              location: 'London' },
            { slug: 'hundred-w-trent', name: 'Trent Rockets (W)',   short_name: 'Trent Rockets',
              location: 'Nottingham' },
            { slug: 'hundred-w-spirit', name: 'London Spirit (W)',  short_name: 'Spirit',
              location: 'London' }
          ]
        }
      ]
    },

    'golf' => {
      name: 'Golf',
      emoji: '⛳',
      region: 'global',
      blurb: 'PGA + LPGA + DP World + LET. Majors run across all tours.',
      leagues: [
        {
          slug: 'pga-tour', name: 'PGA Tour', sport: 'golf', women: false,
          region: 'us', country: 'US',
          blurb: 'Top men\'s professional tour.',
          teams: [
            { slug: 'golf-scheffler', name: 'Scottie Scheffler', short_name: 'Scheffler',
              location: 'USA' },
            { slug: 'golf-mcilroy',   name: 'Rory McIlroy',      short_name: 'McIlroy',
              location: 'Northern Ireland' },
            { slug: 'golf-rahm',      name: 'Jon Rahm',          short_name: 'Rahm',
              location: 'Spain' },
            { slug: 'golf-schauffele', name: 'Xander Schauffele', short_name: 'Schauffele',
              location: 'USA' },
            { slug: 'golf-koepka',    name: 'Brooks Koepka',     short_name: 'Koepka',
              location: 'USA' }
          ]
        },
        {
          slug: 'lpga', name: 'LPGA Tour', sport: 'golf', women: true,
          region: 'us', country: 'US',
          blurb: 'Top women\'s professional tour.',
          teams: [
            { slug: 'lpga-korda',    name: 'Nelly Korda',       short_name: 'Korda',
              location: 'USA' },
            { slug: 'lpga-ko',       name: 'Lydia Ko',          short_name: 'Ko',
              location: 'New Zealand' },
            { slug: 'lpga-thitikul', name: 'Atthaya Thitikul',  short_name: 'Thitikul',
              location: 'Thailand' },
            { slug: 'lpga-zhang',    name: 'Rose Zhang',        short_name: 'Zhang',
              location: 'USA' },
            { slug: 'lpga-furue',    name: 'Ayaka Furue',       short_name: 'Furue',
              location: 'Japan' }
          ]
        },
        {
          slug: 'dp-world-tour', name: 'DP World Tour', sport: 'golf', women: false,
          region: 'europe', country: nil,
          blurb: 'European men\'s tour (formerly European Tour).',
          teams: [
            { slug: 'dp-fleetwood', name: 'Tommy Fleetwood', short_name: 'Fleetwood',
              location: 'England' },
            { slug: 'dp-hovland',   name: 'Viktor Hovland',  short_name: 'Hovland',
              location: 'Norway' },
            { slug: 'dp-rai',       name: 'Aaron Rai',       short_name: 'Rai',
              location: 'England' }
          ]
        },
        {
          slug: 'ladies-european', name: 'Ladies European Tour', sport: 'golf', women: true,
          region: 'europe', country: nil,
          blurb: "Europe's women's tour.",
          teams: [
            { slug: 'let-pedersen', name: 'Emily Kristine Pedersen', short_name: 'Pedersen',
              location: 'Denmark' },
            { slug: 'let-hall',     name: 'Georgia Hall',     short_name: 'Hall',
              location: 'England' },
            { slug: 'let-grant',    name: 'Linn Grant',       short_name: 'Grant',
              location: 'Sweden' }
          ]
        },
        {
          slug: 'liv-golf', name: 'LIV Golf', sport: 'golf', women: false,
          region: 'global', country: nil,
          blurb: 'Saudi-backed breakaway league; team-based 54-hole format.',
          teams: [
            { slug: 'liv-4aces',     name: '4Aces GC',     short_name: '4Aces',
              location: 'USA' },
            { slug: 'liv-rangegoats', name: 'RangeGoats GC', short_name: 'RangeGoats',
              location: 'USA' },
            { slug: 'liv-stinger',   name: 'Stinger GC',   short_name: 'Stinger',
              location: 'South Africa' },
            { slug: 'liv-fireballs', name: 'Fireballs GC', short_name: 'Fireballs',
              location: 'Spain' }
          ]
        }
      ]
    },

    'badminton' => {
      name: 'Badminton',
      emoji: '🏸',
      region: 'global',
      blurb: 'BWF World Tour. Indonesia, Denmark, China, Japan dominate; talent global.',
      leagues: [
        {
          slug: 'bwf-mens', name: "BWF World Tour — Men's Singles", sport: 'badminton', women: false,
          region: 'global', country: nil,
          blurb: 'BWF flagship men\'s singles tour.',
          teams: [
            { slug: 'bwf-axelsen',    name: 'Viktor Axelsen',     short_name: 'Axelsen',
              location: 'Denmark' },
            { slug: 'bwf-shi-yuqi',   name: 'Shi Yuqi',           short_name: 'Shi Yuqi',
              location: 'China' },
            { slug: 'bwf-momota',     name: 'Kento Momota',       short_name: 'Momota',
              location: 'Japan' },
            { slug: 'bwf-ginting',    name: 'Anthony Ginting',    short_name: 'Ginting',
              location: 'Indonesia' },
            { slug: 'bwf-lakshya-sen', name: 'Lakshya Sen',       short_name: 'Lakshya Sen',
              location: 'India' }
          ]
        },
        {
          slug: 'bwf-womens', name: "BWF World Tour — Women's Singles", sport: 'badminton', women: true,
          region: 'global', country: nil,
          blurb: 'BWF flagship women\'s singles tour.',
          teams: [
            { slug: 'bwf-an-se-young', name: 'An Se-young',       short_name: 'An Se-young',
              location: 'South Korea' },
            { slug: 'bwf-yamaguchi',   name: 'Akane Yamaguchi',   short_name: 'Yamaguchi',
              location: 'Japan' },
            { slug: 'bwf-chen-yufei',  name: 'Chen Yufei',        short_name: 'Chen Yufei',
              location: 'China' },
            { slug: 'bwf-marin',       name: 'Carolina Marín',    short_name: 'Marín',
              location: 'Spain' },
            { slug: 'bwf-sindhu',      name: 'P. V. Sindhu',      short_name: 'Sindhu',
              location: 'India' }
          ]
        }
      ]
    },

    'horse-racing' => {
      name: 'Horse Racing',
      emoji: '🐎',
      region: 'global',
      blurb: 'Flat + jumps. Triple Crowns in US + UK; Dubai\'s World Cup is the richest single day.',
      leagues: [
        {
          slug: 'us-triple-crown', name: 'US Triple Crown', sport: 'horse-racing', women: false,
          region: 'us', country: 'US',
          blurb: 'Kentucky Derby → Preakness → Belmont. Three races, five weeks.',
          teams: [
            { slug: 'race-kentucky-derby', name: 'Kentucky Derby',
              short_name: 'Kentucky Derby', location: 'Louisville, KY' },
            { slug: 'race-preakness',      name: 'Preakness Stakes',
              short_name: 'Preakness',     location: 'Baltimore, MD' },
            { slug: 'race-belmont',        name: 'Belmont Stakes',
              short_name: 'Belmont',       location: 'New York, NY' },
            { slug: 'race-breeders-cup',   name: "Breeders' Cup World Championships",
              short_name: "Breeders' Cup", location: 'USA' }
          ]
        },
        {
          slug: 'uk-flat', name: 'UK Flat Racing', sport: 'horse-racing', women: false,
          region: 'europe', country: 'GB',
          blurb: 'Royal Ascot, the Derby at Epsom, St Leger — Britain\'s classic flat-racing schedule.',
          teams: [
            { slug: 'race-royal-ascot',    name: 'Royal Ascot',          short_name: 'Royal Ascot',
              location: 'Ascot, England' },
            { slug: 'race-epsom-derby',    name: 'Epsom Derby',          short_name: 'Epsom Derby',
              location: 'Epsom, England' },
            { slug: 'race-st-leger',       name: 'St Leger Stakes',      short_name: 'St Leger',
              location: 'Doncaster, England' },
            { slug: 'race-2000-guineas',   name: '2000 Guineas',         short_name: '2000 Guineas',
              location: 'Newmarket, England' }
          ]
        },
        {
          slug: 'uk-jumps', name: 'UK Jumps Racing', sport: 'horse-racing', women: false,
          region: 'europe', country: 'GB',
          blurb: "Cheltenham Festival + Grand National headline the National Hunt calendar.",
          teams: [
            { slug: 'race-cheltenham',     name: 'Cheltenham Festival', short_name: 'Cheltenham',
              location: 'Cheltenham, England' },
            { slug: 'race-grand-national', name: 'Grand National',      short_name: 'Grand National',
              location: 'Aintree, England' }
          ]
        },
        {
          slug: 'dubai-world-cup', name: 'Dubai World Cup', sport: 'horse-racing', women: false,
          region: 'middle-east', country: 'AE',
          blurb: 'The richest single-day card in racing. UAE\'s flagship meeting.',
          teams: [
            { slug: 'race-dubai-world-cup', name: 'Dubai World Cup',    short_name: 'Dubai World Cup',
              location: 'Meydan, UAE' },
            { slug: 'race-dubai-turf',      name: 'Dubai Turf',         short_name: 'Dubai Turf',
              location: 'Meydan, UAE' }
          ]
        }
      ]
    }
  }.freeze

  # Flat: every league across every sport. Useful for store-seed scripts.
  def all_leagues
    SPORTS.flat_map { |sport_slug, sport| sport[:leagues].map { |lg| lg.merge(sport_slug: sport_slug) } }
  end

  # Flat: every team across every league.
  def all_teams
    all_leagues.flat_map do |lg|
      (lg[:teams] || []).map { |t| t.merge(league_slug: lg[:slug], sport_slug: lg[:sport_slug]) }
    end
  end

  # Lookup helpers used by the /sports/manage drill-down routes.
  def find_sport(sport_slug)
    s = SPORTS[sport_slug.to_s]
    return nil unless s
    s.merge(slug: sport_slug.to_s)
  end

  def find_league(sport_slug, league_slug)
    sport = SPORTS[sport_slug.to_s]
    return nil unless sport
    lg = sport[:leagues].find { |x| x[:slug] == league_slug.to_s }
    return nil unless lg
    lg.merge(sport_slug: sport_slug.to_s)
  end

  def find_team(team_slug)
    all_teams.find { |t| t[:slug] == team_slug.to_s }
  end
end
