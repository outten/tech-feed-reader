import Foundation

struct StockHistoryPoint: Codable, Hashable {
    let t: TimeInterval
    let c: Double

    var date: Date { Date(timeIntervalSince1970: t) }
}

struct StockHistoryResponse: Codable {
    let symbol: String
    let days: Int
    let points: [StockHistoryPoint]
}
