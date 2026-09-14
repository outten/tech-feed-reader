import Foundation

struct StockQuote: Codable, Hashable {
    let symbol: String
    let name: String?
    let exchange: String?
    let price: Double?
    let change: Double?
    let changePct: Double?
    let dayHigh: Double?
    let dayLow: Double?
    let open: Double?
    let prevClose: Double?

    enum CodingKeys: String, CodingKey {
        case symbol, name, exchange, price, change
        case changePct = "change_pct"
        case dayHigh = "day_high"
        case dayLow = "day_low"
        case open
        case prevClose = "prev_close"
    }
}

struct StockDetail: Codable {
    let quote: StockQuote?
    let followed: Bool
}

struct StockSearchResult: Identifiable, Codable, Hashable {
    let symbol: String
    let description: String?
    let type: String?

    var id: String { symbol }
}

/// Ticker rows are name-only for a not-yet-cached symbol/index — most
/// fields are absent, so this is intentionally its own lighter type
/// rather than reusing StockQuote (whose non-optional expectations
/// don't apply here).
struct TickerEntry: Identifiable, Codable, Hashable {
    let symbol: String
    let name: String?
    let price: Double?
    let change: Double?
    let changePct: Double?

    var id: String { symbol }

    enum CodingKeys: String, CodingKey {
        case symbol, name, price, change
        case changePct = "change_pct"
    }
}
