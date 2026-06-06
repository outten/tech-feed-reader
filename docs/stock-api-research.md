# Stock Market API & Finance RSS Research

## Stock Market APIs

### 1. Yahoo Finance (Unofficial)

**Endpoints:**
- Chart/Quote: `query1.finance.yahoo.com/v8/finance/chart/{SYMBOL}`
- Search: `query1.finance.yahoo.com/v1/finance/search?q={QUERY}`
- Quote summary: `query1.finance.yahoo.com/v10/finance/quoteSummary/{SYMBOL}`

**API Key Required:** No
**Rate Limits:** Unofficial/undocumented. Aggressive rate limiting observed (429 errors common). No guaranteed SLA.
**Data Freshness:** Real-time during market hours (15-min delayed for some endpoints)
**Pros:** No API key needed, comprehensive data, free
**Cons:** Unofficial API - can break without notice. Yahoo actively rate-limits and blocks scrapers. Returns 429 frequently. No official support.
**Risk Level:** HIGH - not recommended for production use

**Sample curl:**
```bash
curl "https://query1.finance.yahoo.com/v8/finance/chart/AAPL?interval=1d&range=1d"
```

**Verdict:** Too unreliable. Use as last-resort fallback only.

---

### 2. Alpha Vantage (Free Tier)

**Endpoints:**
- Global Quote: `/query?function=GLOBAL_QUOTE&symbol={SYMBOL}`
- Symbol Search: `/query?function=SYMBOL_SEARCH&keywords={QUERY}`
- Company Overview: `/query?function=OVERVIEW&symbol={SYMBOL}`

**API Key Required:** Yes (free, instant signup at alphavantage.co)
**Rate Limits:** 25 requests/day on free tier (was 500/day, reduced significantly)
**Data Freshness:** Real-time for US equities
**Pros:** Official API, well-documented, includes company overview data
**Cons:** Extremely low free tier (25 req/day makes it nearly unusable for a feed reader). Premium starts at $49.99/mo.

**Sample curl:**
```bash
curl "https://www.alphavantage.co/query?function=GLOBAL_QUOTE&symbol=AAPL&apikey=YOUR_KEY"
```

**Verdict:** Free tier too restrictive (25 req/day). Not viable unless upgrading to paid.

---

### 3. Finnhub (Free Tier) - RECOMMENDED FOR QUOTES

**Endpoints:**
- Quote: `/api/v1/quote?symbol={SYMBOL}`
- Symbol Search: `/api/v1/search?q={QUERY}`
- Company Profile: `/api/v1/stock/profile2?symbol={SYMBOL}`

**API Key Required:** Yes (free signup at finnhub.io)
**Rate Limits:** 60 API calls/minute on free tier
**Data Freshness:** Real-time US stock data
**Pros:** Generous free tier (60/min), real-time data, WebSocket support, company profiles, financial news endpoint
**Cons:** Some endpoints (earnings, financials) limited on free tier

**Sample curl:**
```bash
curl "https://finnhub.io/api/v1/quote?symbol=AAPL&token=YOUR_KEY"
# Returns: {"c":207.15,"d":-1.35,"dp":-0.647,"h":209.52,"l":206.16,"o":208.37,"pc":208.50,"t":1234567890}
# c=current, d=change, dp=%change, h=high, l=low, o=open, pc=previous close
```

**Verdict:** RECOMMENDED - Best free tier for real-time quotes. 60 req/min is very generous.

---

### 4. Twelve Data (Free Tier)

**Endpoints:**
- Quote: `/quote?symbol={SYMBOL}`
- Symbol Search: `/symbol_search?symbol={QUERY}`
- Time Series: `/time_series?symbol={SYMBOL}&interval=1day`
- (No company profile/description endpoint on free tier)

**API Key Required:** Yes (free signup at twelvedata.com)
**Rate Limits:** 8 API calls/minute, 800 calls/day on free tier
**Data Freshness:** End-of-day on free tier (real-time requires paid plan)
**Pros:** Clean JSON responses, good symbol search, 52-week data included in quote
**Cons:** Only 8 req/min on free tier, end-of-day data only (not real-time), no company description/profile on free tier

**Sample curl (verified working with demo key):**
```bash
curl "https://api.twelvedata.com/quote?symbol=AAPL&apikey=YOUR_KEY"
# Returns: {"symbol":"AAPL","name":"Apple Inc.","exchange":"NASDAQ","currency":"USD",
#   "open":"312.99","high":"315.17","low":"307.15","close":"307.34",
#   "volume":"64824174","previous_close":"311.23","change":"-3.89",
#   "percent_change":"-1.25","average_volume":"51426337",
#   "fifty_two_week":{"low":"195.07","high":"316.94",...}}

curl "https://api.twelvedata.com/symbol_search?symbol=Apple&outputsize=3&apikey=YOUR_KEY"
# Returns list of matching symbols with exchange info
```

**Verdict:** Good for basic quote data. The 8 req/min limit is workable for a ticker display.

---

### 5. Financial Modeling Prep (Free Tier) - RECOMMENDED FOR COMPANY INFO

**Endpoints:**
- Quote: `/api/v3/quote/{SYMBOL}`
- Search: `/api/v3/search?query={QUERY}`
- Company Profile: `/api/v3/profile/{SYMBOL}` (includes description, sector, industry, market cap)

**API Key Required:** Yes (free signup at financialmodelingprep.com)
**Rate Limits:** 250 API calls/day on free tier
**Data Freshness:** Real-time for quotes
**Pros:** Rich company profile data (description, CEO, sector, industry, full address, logo URL), 250 req/day is decent
**Cons:** Demo key doesn't work (must register). Some historical data limited on free tier.

**Sample curl:**
```bash
curl "https://financialmodelingprep.com/api/v3/quote/AAPL?apikey=YOUR_KEY"
curl "https://financialmodelingprep.com/api/v3/profile/AAPL?apikey=YOUR_KEY"
# Profile returns: name, description, sector, industry, CEO, website, image/logo, market cap, etc.
```

**Verdict:** RECOMMENDED for company profiles/info. Best free source for company descriptions and sector data.

---

## Recommended API Strategy

| Use Case | Primary API | Fallback |
|-----------|------------|----------|
| Real-time quotes (price, change, volume) | **Finnhub** (60/min) | Twelve Data (8/min) |
| Symbol search/lookup | **Finnhub** or **Twelve Data** | - |
| Company info (sector, description) | **Financial Modeling Prep** (250/day) | Finnhub profile |
| 52-week range, avg volume | **Twelve Data** | - |

**Total API keys needed:** 3 (Finnhub, Twelve Data, FMP) - all free, instant signup.

---

## Financial News RSS Feeds

All feeds tested and verified on 2026-06-05.

### Working and Recommended

| Source | Feed URL | Status | Content |
|--------|----------|--------|---------|
| **CNBC Top News** | `https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=100003114` | 200 OK | US business/market news, ~30 items |
| **CNBC Finance** | `https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=15839069` | 200 OK | Finance-specific |
| **CNBC Economy** | `https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=10000664` | 200 OK | Economy news |
| **MarketWatch Top Stories** | `https://feeds.content.dowjones.io/public/rss/mw_topstories` | 200 OK | Market/business news with images |
| **Seeking Alpha News** | `https://seekingalpha.com/market_currents.xml` | 200 OK | Breaking market news, includes ticker symbols |
| **Google News Business** | See URL below | 200 OK | Aggregated business news from multiple sources |

Google News Business URL:
`https://news.google.com/rss/topics/CAAqJggKIiBDQkFTRWdvSUwyMHZNRGx6TVdZU0FtVnVHZ0pWVXlnQVAB?hl=en-US&gl=US&ceid=US:en`

### Additional CNBC Feeds

- CNBC Technology: `https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=19854910`
- CNBC Earnings: `https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=15839135`

### Additional MarketWatch Feeds

- MW Market Pulse: `https://feeds.content.dowjones.io/public/rss/mw_marketpulse`
- MW Stocks to Watch: `https://feeds.content.dowjones.io/public/rss/mw_stockstowatch`

### Not Working / Restricted

| Source | Status | Notes |
|--------|--------|-------|
| **Yahoo Finance RSS** | 429 | Aggressive rate limiting, unreliable |
| **Bloomberg** | Blocked | No public RSS feeds available |
| **Reuters Business** | DNS fail | feeds.reuters.com no longer resolves; discontinued |
| **Motley Fool** | 404 | Feed URLs return 404; appears discontinued |

---

## Recommended Finance/Markets Feed Catalog (JSON)

```json
{
  "topic": "Finance / Markets",
  "feeds": [
    {
      "name": "CNBC Top News",
      "url": "https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=100003114",
      "category": "markets"
    },
    {
      "name": "CNBC Investing",
      "url": "https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=15839069",
      "category": "investing"
    },
    {
      "name": "CNBC Economy",
      "url": "https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=10000664",
      "category": "economy"
    },
    {
      "name": "MarketWatch Top Stories",
      "url": "https://feeds.content.dowjones.io/public/rss/mw_topstories",
      "category": "markets"
    },
    {
      "name": "MarketWatch Stocks to Watch",
      "url": "https://feeds.content.dowjones.io/public/rss/mw_stockstowatch",
      "category": "stocks"
    },
    {
      "name": "Seeking Alpha Breaking News",
      "url": "https://seekingalpha.com/market_currents.xml",
      "category": "breaking"
    },
    {
      "name": "Google News - Business",
      "url": "https://news.google.com/rss/topics/CAAqJggKIiBDQkFTRWdvSUwyMHZNRGx6TVdZU0FtVnVHZ0pWVXlnQVAB?hl=en-US&gl=US&ceid=US:en",
      "category": "business"
    }
  ]
}
```
