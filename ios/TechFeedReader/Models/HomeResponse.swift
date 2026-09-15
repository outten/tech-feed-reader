import Foundation

struct HomeStats: Codable {
    let unread: Int
    let bookmarks: Int
    let articles: Int
}

/// Phase 14 — GET /api/v1/home bundles what the web `/` dashboard's
/// load_whats_on_today! helper assembles, minus YouTube-fallback padding
/// and continue-watching (see design.md).
struct HomeResponse: Codable {
    let stats: HomeStats
    let todayMatches: [SportsMatch]
    let liveMatches: [SportsMatch]
    let todayReading: [Article]
    let todayListening: [Article]
    let todayWatching: [Article]
}
