## NEW Requirements

### Requirement: Store currency alongside market cap
When fetching a stock profile from Finnhub, the app SHALL store the `currency` field from the profile2 response in the `stock_quotes` table. The `currency` column is `VARCHAR(10)`, nullable.

#### Scenario: Profile with currency
- **WHEN** Finnhub profile2 returns `{ "marketCapitalization": 60000000, "currency": "TWD", ... }`
- **THEN** `stock_quotes` stores `market_cap = 60_000_000_000_000` (millions → raw) and `currency = "TWD"`

#### Scenario: Profile without currency (graceful)
- **WHEN** Finnhub profile2 does not include a `currency` field
- **THEN** `currency` is stored as `NULL`; existing behaviour is unchanged

### Requirement: Display market cap with currency context
The stock detail page SHALL display market cap with the correct currency prefix (USD) or suffix (non-USD currency code) so users can distinguish local-currency values from USD.

#### Scenario: USD market cap (e.g., AAPL)
- **WHEN** `currency` is `"USD"` (or nil, defaulting to USD formatting)
- **THEN** market cap displays as `$1.23T`, `$456.78B`, `$12.34M`

#### Scenario: Non-USD market cap (e.g., TSM in TWD)
- **WHEN** `currency` is `"TWD"`
- **THEN** market cap displays as `TWD 60.00T` (no `$` prefix, currency code suffix)

#### Scenario: Null currency (legacy row before column was added)
- **WHEN** `currency` is `NULL` in the database
- **THEN** `format_market_cap` receives `nil`; falls back to the no-prefix/no-suffix form (e.g., `60.00T`)
