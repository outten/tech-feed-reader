import Foundation

struct TennisRankings: Codable {
    let atp: [SportsPlayer]
    let wta: [SportsPlayer]
    let followedPlayerSlugs: [String]
}
